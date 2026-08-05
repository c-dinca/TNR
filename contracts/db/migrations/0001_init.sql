-- 0001_init.sql — TNR-OS initial schema
--
-- NORMATIVE. This file is the source of truth for the database schema.
-- Rationale and invariants: docs/02-architecture/02-data-model.md
--
-- Rules (docs/03-adr/0005-postgres-postgis-drizzle.md):
--   * forward-only; never edit this file once applied anywhere
--   * all ids are UUIDv7, generated client-side for offline-created entities
--   * every tenant table has org_id NOT NULL and deleted_at
--   * all timestamps are timestamptz, UTC, named *_at
--   * all locations are geography(Point, 4326) — longitude first

BEGIN;

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

CREATE TYPE membership_role     AS ENUM ('owner','admin','coordinator','vet','volunteer','funder');
CREATE TYPE sighting_source     AS ENUM ('field_app','import','device');
CREATE TYPE sighting_status     AS ENUM ('active','duplicate','rejected');
CREATE TYPE pack_status         AS ENUM ('proposed','active','closed');
CREATE TYPE pack_closed_reason  AS ENUM ('resolved','relocated','duplicate','erroneous');
CREATE TYPE pack_estimate_method AS ENUM ('field_report','max_observed','mean_recent','manual');
CREATE TYPE animal_sex          AS ENUM ('unknown','male','female');
CREATE TYPE ear_notch_status    AS ENUM ('unknown','none','left','right','both');
CREATE TYPE sterilisation_status AS ENUM ('unknown','reported_sterilised','confirmed_sterilised','not_sterilised');
CREATE TYPE intervention_type   AS ENUM ('sterilisation','vaccination_rabies','microchip_implant','treatment','examination','euthanasia');
CREATE TYPE mission_status      AS ENUM ('draft','planned','in_progress','completed','cancelled');
CREATE TYPE optimisation_mode   AS ENUM ('optimised','fallback_straight_line','manual');
CREATE TYPE stop_type           AS ENUM ('pack','clinic','depot','fuel','handover');
CREATE TYPE stop_outcome        AS ENUM ('pending','arrived','completed','skipped');
CREATE TYPE media_status        AS ENUM ('pending','uploaded','processed','quarantined','failed');
CREATE TYPE media_variant       AS ENUM ('original','web','thumb');
CREATE TYPE media_entity_type   AS ENUM ('sighting','intervention','animal','pack','report');
CREATE TYPE media_role          AS ENUM ('general','before','after','evidence');
CREATE TYPE audit_actor_type    AS ENUM ('user','system','device');
CREATE TYPE campaign_status     AS ENUM ('planned','active','completed','cancelled');
CREATE TYPE report_kind         AS ENUM ('donor_pdf','evidence_pack','recs_csv');
CREATE TYPE job_status          AS ENUM ('queued','running','succeeded','failed');
CREATE TYPE device_kind         AS ENUM ('trap_sensor');
CREATE TYPE device_status       AS ENUM ('provisioned','active','inactive','lost');

-- ---------------------------------------------------------------------------
-- Reference data (not tenant-scoped)
-- ---------------------------------------------------------------------------

CREATE TABLE locality (
  id                     uuid PRIMARY KEY,
  siruta_code            text UNIQUE,
  name                   text NOT NULL,
  county                 text NOT NULL,
  type                   text NOT NULL,
  geometry               geography(MultiPolygon, 4326),
  centroid               geography(Point, 4326),
  population_estimate    integer,
  -- provenance is displayed with every coverage figure; see OQ-DM-3
  dog_population_estimate integer,
  dog_population_source  text,
  created_at             timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_locality_geometry ON locality USING GIST (geometry);
CREATE INDEX idx_locality_county   ON locality (county);

-- ---------------------------------------------------------------------------
-- Tenancy and identity
-- ---------------------------------------------------------------------------

CREATE TABLE org (
  id                   uuid PRIMARY KEY,
  name                 text NOT NULL,
  country              char(2) NOT NULL DEFAULT 'RO',
  default_locale       text NOT NULL DEFAULT 'ro',
  timezone             text NOT NULL DEFAULT 'Europe/Bucharest',
  subscription_tier    text NOT NULL DEFAULT 'field',
  cluster_radius_m     integer NOT NULL DEFAULT 300,
  cluster_window_days  integer NOT NULL DEFAULT 90,
  -- audit chain head; updated only by the audit append routine, in-transaction
  audit_head_hash      text,
  audit_head_seq       bigint NOT NULL DEFAULT 0,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  deleted_at           timestamptz,
  CONSTRAINT ck_org_cluster_radius CHECK (cluster_radius_m BETWEEN 10 AND 10000)
);

CREATE TABLE app_user (
  id                 uuid PRIMARY KEY,
  email              text,
  -- lowercased, trimmed; the uniqueness key. `email` keeps the form the user typed.
  email_normalised   text NOT NULL,
  password_hash      text,
  display_name       text NOT NULL,
  locale             text NOT NULL DEFAULT 'ro',
  is_pseudonymised   boolean NOT NULL DEFAULT false,
  last_login_at      timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  deleted_at         timestamptz
);
CREATE UNIQUE INDEX uq_app_user_email ON app_user (email_normalised) WHERE deleted_at IS NULL;

CREATE TABLE membership (
  id           uuid PRIMARY KEY,
  org_id       uuid NOT NULL REFERENCES org(id),
  user_id      uuid NOT NULL REFERENCES app_user(id),
  role         membership_role NOT NULL,
  is_active    boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  deleted_at   timestamptz,
  CONSTRAINT uq_membership_user_org UNIQUE (org_id, user_id)
);
CREATE INDEX idx_membership_user ON membership (user_id) WHERE deleted_at IS NULL;

CREATE TABLE invitation (
  id            uuid PRIMARY KEY,
  org_id        uuid NOT NULL REFERENCES org(id),
  email         text NOT NULL,
  role          membership_role NOT NULL,
  token_hash    text NOT NULL,
  invited_by    uuid NOT NULL REFERENCES app_user(id),
  expires_at    timestamptz NOT NULL,
  accepted_at   timestamptz,
  revoked_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_invitation_org ON invitation (org_id) WHERE accepted_at IS NULL AND revoked_at IS NULL;

CREATE TABLE refresh_token (
  id            uuid PRIMARY KEY,
  user_id       uuid NOT NULL REFERENCES app_user(id),
  family_id     uuid NOT NULL,
  token_hash    text NOT NULL UNIQUE,
  device_label  text,
  ip_country    char(2),
  expires_at    timestamptz NOT NULL,
  used_at       timestamptz,
  revoked_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  last_used_at  timestamptz
);
CREATE INDEX idx_refresh_token_family ON refresh_token (family_id);
CREATE INDEX idx_refresh_token_user   ON refresh_token (user_id) WHERE revoked_at IS NULL;

-- ---------------------------------------------------------------------------
-- Devices (Phase 2 seam — table only; see docs/02-architecture/12-phase-2-iot-seams.md)
-- ---------------------------------------------------------------------------

CREATE TABLE device (
  id                uuid PRIMARY KEY,
  org_id            uuid NOT NULL REFERENCES org(id),
  hardware_id       text NOT NULL UNIQUE,
  label             text,
  kind              device_kind NOT NULL DEFAULT 'trap_sensor',
  status            device_status NOT NULL DEFAULT 'provisioned',
  credential_hash   text,
  firmware_version  text,
  assigned_pack_id  uuid,
  last_seen_at      timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz
);

-- ---------------------------------------------------------------------------
-- Packs
-- ---------------------------------------------------------------------------

CREATE TABLE pack (
  id                      uuid PRIMARY KEY,
  org_id                  uuid NOT NULL REFERENCES org(id),
  name                    text,
  centroid                geography(Point, 4326),
  centroid_is_manual      boolean NOT NULL DEFAULT false,
  area                    geography(Polygon, 4326),
  locality_id             uuid REFERENCES locality(id),
  animal_count_estimate   integer,
  estimate_method         pack_estimate_method NOT NULL DEFAULT 'field_report',
  notched_ratio_observed  numeric(4,3),
  status                  pack_status NOT NULL DEFAULT 'proposed',
  closed_reason           pack_closed_reason,
  merged_into_pack_id     uuid REFERENCES pack(id),
  version                 integer NOT NULL DEFAULT 1,
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now(),
  deleted_at              timestamptz,
  CONSTRAINT ck_pack_closed_reason CHECK (status <> 'closed' OR closed_reason IS NOT NULL),
  CONSTRAINT ck_pack_merged        CHECK (merged_into_pack_id IS NULL
                                          OR (status = 'closed' AND closed_reason = 'duplicate')),
  CONSTRAINT ck_pack_notch_ratio   CHECK (notched_ratio_observed IS NULL
                                          OR notched_ratio_observed BETWEEN 0 AND 1)
);
CREATE INDEX idx_pack_centroid ON pack USING GIST (centroid);
CREATE INDEX idx_pack_org_status ON pack (org_id, status) WHERE deleted_at IS NULL;
CREATE INDEX idx_pack_locality ON pack (locality_id) WHERE deleted_at IS NULL;

ALTER TABLE device ADD CONSTRAINT fk_device_pack
  FOREIGN KEY (assigned_pack_id) REFERENCES pack(id);

-- ---------------------------------------------------------------------------
-- Sightings
-- ---------------------------------------------------------------------------

CREATE TABLE sighting (
  id                      uuid PRIMARY KEY,   -- client-generated UUIDv7
  org_id                  uuid NOT NULL REFERENCES org(id),
  location                geography(Point, 4326) NOT NULL,
  location_accuracy_m     integer,
  occurred_at             timestamptz NOT NULL,
  animal_count_estimate   integer NOT NULL,
  notched_count_observed  integer NOT NULL DEFAULT 0,
  health_note             text,
  reported_by_user_id     uuid REFERENCES app_user(id),
  source                  sighting_source NOT NULL DEFAULT 'field_app',
  device_id               uuid REFERENCES device(id),
  status                  sighting_status NOT NULL DEFAULT 'active',
  client_created_at       timestamptz,
  clock_skew_ms           integer,
  created_at              timestamptz NOT NULL DEFAULT now(),
  deleted_at              timestamptz,
  CONSTRAINT ck_sighting_count   CHECK (animal_count_estimate >= 1),
  CONSTRAINT ck_sighting_notched CHECK (notched_count_observed >= 0
                                        AND notched_count_observed <= animal_count_estimate),
  -- Phase 2 seam: a device-originated sighting has no human author
  CONSTRAINT ck_sighting_device  CHECK (source <> 'device' OR device_id IS NOT NULL),
  CONSTRAINT ck_sighting_author  CHECK (source = 'device' OR reported_by_user_id IS NOT NULL)
);
CREATE INDEX idx_sighting_location ON sighting USING GIST (location);
CREATE INDEX idx_sighting_org_time ON sighting (org_id, occurred_at DESC);
CREATE INDEX idx_sighting_org_status ON sighting (org_id, status) WHERE deleted_at IS NULL;
CREATE INDEX idx_sighting_reporter ON sighting (reported_by_user_id, occurred_at DESC);

-- Many-to-many so a clustering decision stays reversible (unlinked_at, not DELETE)
CREATE TABLE sighting_pack (
  id           uuid PRIMARY KEY,
  org_id       uuid NOT NULL REFERENCES org(id),
  sighting_id  uuid NOT NULL REFERENCES sighting(id),
  pack_id      uuid NOT NULL REFERENCES pack(id),
  linked_by    text NOT NULL CHECK (linked_by IN ('auto','manual')),
  confidence   numeric(4,3),
  linked_at    timestamptz NOT NULL DEFAULT now(),
  unlinked_at  timestamptz
);
CREATE UNIQUE INDEX uq_sighting_pack_active
  ON sighting_pack (sighting_id, pack_id) WHERE unlinked_at IS NULL;
CREATE INDEX idx_sighting_pack_pack ON sighting_pack (pack_id) WHERE unlinked_at IS NULL;

-- ---------------------------------------------------------------------------
-- Animals
-- ---------------------------------------------------------------------------

CREATE TABLE animal (
  id                        uuid PRIMARY KEY,   -- client-generated UUIDv7
  org_id                    uuid NOT NULL REFERENCES org(id),
  microchip                 text,
  is_romanian_chip          boolean,
  name                      text,
  sex                       animal_sex NOT NULL DEFAULT 'unknown',
  estimated_birth_year      integer,
  size_class                text,
  coat_description          text,
  ear_notch_status          ear_notch_status NOT NULL DEFAULT 'unknown',
  is_owned                  boolean NOT NULL DEFAULT false,
  -- free label only; MUST NOT contain owner personal data (FR-057)
  household_ref             text,
  -- derived from interventions; never client-set except reported_sterilised (FR-058)
  sterilisation_status      sterilisation_status NOT NULL DEFAULT 'unknown',
  chip_lookup_provider      text,
  chip_lookup_found         boolean,
  chip_lookup_checked_at    timestamptz,
  chip_lookup_raw           jsonb,
  created_at                timestamptz NOT NULL DEFAULT now(),
  updated_at                timestamptz NOT NULL DEFAULT now(),
  deleted_at                timestamptz,
  -- ISO 11784/11785: exactly 15 numeric digits. Non-642 prefixes are valid (FR-051)
  CONSTRAINT ck_animal_microchip_format CHECK (microchip IS NULL OR microchip ~ '^[0-9]{15}$')
);
CREATE UNIQUE INDEX uq_animal_microchip_org
  ON animal (org_id, microchip) WHERE microchip IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX idx_animal_org ON animal (org_id) WHERE deleted_at IS NULL;

CREATE TABLE animal_pack (
  id          uuid PRIMARY KEY,
  org_id      uuid NOT NULL REFERENCES org(id),
  animal_id   uuid NOT NULL REFERENCES animal(id),
  pack_id     uuid NOT NULL REFERENCES pack(id),
  valid_from  timestamptz NOT NULL DEFAULT now(),
  valid_to    timestamptz
);
CREATE UNIQUE INDEX uq_animal_pack_open ON animal_pack (animal_id) WHERE valid_to IS NULL;
CREATE INDEX idx_animal_pack_pack ON animal_pack (pack_id);

-- ---------------------------------------------------------------------------
-- Campaigns, grants, vehicles
-- ---------------------------------------------------------------------------

CREATE TABLE grant_record (
  id                       uuid PRIMARY KEY,
  org_id                   uuid NOT NULL REFERENCES org(id),
  donor_name               text NOT NULL,
  reference                text,
  reporting_period_start   date,
  reporting_period_end     date,
  required_metrics         jsonb,
  contact_email            text,
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now(),
  deleted_at               timestamptz
);

CREATE TABLE campaign (
  id                        uuid PRIMARY KEY,
  org_id                    uuid NOT NULL REFERENCES org(id),
  grant_id                  uuid REFERENCES grant_record(id),
  name                      text NOT NULL,
  starts_on                 date NOT NULL,
  ends_on                   date,
  target_intervention_count integer,
  budget_amount             numeric(12,2),
  budget_currency           char(3),
  scope_area                geography(Polygon, 4326),
  status                    campaign_status NOT NULL DEFAULT 'planned',
  created_at                timestamptz NOT NULL DEFAULT now(),
  updated_at                timestamptz NOT NULL DEFAULT now(),
  deleted_at                timestamptz,
  CONSTRAINT ck_campaign_dates CHECK (ends_on IS NULL OR ends_on >= starts_on)
);
CREATE INDEX idx_campaign_org ON campaign (org_id) WHERE deleted_at IS NULL;

-- Explicit funder access: (membership, campaign) pairs. A funder with no rows sees nothing.
CREATE TABLE funder_campaign_grant (
  id             uuid PRIMARY KEY,
  org_id         uuid NOT NULL REFERENCES org(id),
  membership_id  uuid NOT NULL REFERENCES membership(id),
  campaign_id    uuid NOT NULL REFERENCES campaign(id),
  expires_at     timestamptz,
  revoked_at     timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_funder_grant UNIQUE (membership_id, campaign_id)
);

CREATE TABLE vehicle (
  id               uuid PRIMARY KEY,
  org_id           uuid NOT NULL REFERENCES org(id),
  label            text NOT NULL,
  plate            text,
  cage_capacity    integer NOT NULL DEFAULT 0,
  is_mobile_clinic boolean NOT NULL DEFAULT false,
  is_active        boolean NOT NULL DEFAULT true,
  home_depot       geography(Point, 4326),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  deleted_at       timestamptz,
  CONSTRAINT ck_vehicle_capacity CHECK (cage_capacity >= 0)
);

-- ---------------------------------------------------------------------------
-- Missions
-- ---------------------------------------------------------------------------

CREATE TABLE mission (
  id                    uuid PRIMARY KEY,
  org_id                uuid NOT NULL REFERENCES org(id),
  campaign_id           uuid REFERENCES campaign(id),
  vehicle_id            uuid REFERENCES vehicle(id),
  scheduled_date        date NOT NULL,
  status                mission_status NOT NULL DEFAULT 'draft',
  depot_start           geography(Point, 4326),
  depot_end             geography(Point, 4326),
  window_start_at       timestamptz,
  window_end_at         timestamptz,
  planned_distance_m    integer,
  planned_duration_s    integer,
  -- NULL means unknown and MUST be displayed as unknown, never zero (FR-080)
  actual_distance_m     integer,
  actual_duration_s     integer,
  optimisation_mode     optimisation_mode,
  optimisation_engine   text,
  optimisation_version  text,
  optimised_at          timestamptz,
  version               integer NOT NULL DEFAULT 1,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  deleted_at            timestamptz
);
CREATE INDEX idx_mission_org_date ON mission (org_id, scheduled_date DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_mission_vehicle ON mission (vehicle_id, scheduled_date);

CREATE TABLE mission_member (
  id            uuid PRIMARY KEY,
  org_id        uuid NOT NULL REFERENCES org(id),
  mission_id    uuid NOT NULL REFERENCES mission(id),
  user_id       uuid NOT NULL REFERENCES app_user(id),
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_mission_member UNIQUE (mission_id, user_id)
);

CREATE TABLE mission_stop (
  id                        uuid PRIMARY KEY,
  org_id                    uuid NOT NULL REFERENCES org(id),
  mission_id                uuid NOT NULL REFERENCES mission(id),
  sequence                  integer NOT NULL,
  stop_type                 stop_type NOT NULL DEFAULT 'pack',
  pack_id                   uuid REFERENCES pack(id),
  location                  geography(Point, 4326) NOT NULL,
  eta_at                    timestamptz,
  arrived_at                timestamptz,
  completed_at              timestamptz,
  outcome                   stop_outcome NOT NULL DEFAULT 'pending',
  skip_reason               text,
  animals_captured          integer NOT NULL DEFAULT 0,
  outcome_location          geography(Point, 4326),
  outcome_recorded_offline  boolean NOT NULL DEFAULT false,
  notes                     text,
  created_at                timestamptz NOT NULL DEFAULT now(),
  updated_at                timestamptz NOT NULL DEFAULT now(),
  deleted_at                timestamptz,
  CONSTRAINT ck_stop_skip    CHECK (outcome <> 'skipped' OR skip_reason IS NOT NULL),
  CONSTRAINT ck_stop_capture CHECK (animals_captured >= 0)
);
CREATE UNIQUE INDEX uq_mission_stop_sequence
  ON mission_stop (mission_id, sequence) WHERE deleted_at IS NULL;
CREATE INDEX idx_mission_stop_pack ON mission_stop (pack_id);

-- ---------------------------------------------------------------------------
-- Interventions — append-only (ADR-0018)
-- ---------------------------------------------------------------------------

CREATE TABLE intervention (
  id                          uuid PRIMARY KEY,   -- client-generated UUIDv7
  org_id                      uuid NOT NULL REFERENCES org(id),
  animal_id                   uuid NOT NULL REFERENCES animal(id),
  campaign_id                 uuid REFERENCES campaign(id),
  mission_id                  uuid REFERENCES mission(id),
  mission_stop_id             uuid REFERENCES mission_stop(id),
  type                        intervention_type NOT NULL,
  occurred_at                 timestamptz NOT NULL,
  location                    geography(Point, 4326),
  performed_by_user_id        uuid REFERENCES app_user(id),
  performed_by_vet_name       text NOT NULL,
  vet_licence_ref             text,
  anaesthesia_note            text,
  complication_note           text,
  -- required for euthanasia; never a population-control action (FR-095)
  justification               text,
  ear_notch_applied           ear_notch_status,
  microchip_implanted         text,
  cost_amount                 numeric(12,2),
  cost_currency               char(3),
  supersedes_intervention_id  uuid REFERENCES intervention(id),
  superseded_by_intervention_id uuid REFERENCES intervention(id),
  client_created_at           timestamptz,
  clock_skew_ms               integer,
  created_at                  timestamptz NOT NULL DEFAULT now(),
  deleted_at                  timestamptz,
  CONSTRAINT ck_intervention_euthanasia
    CHECK (type <> 'euthanasia' OR (justification IS NOT NULL AND length(btrim(justification)) > 0)),
  CONSTRAINT ck_intervention_cost
    CHECK ((cost_amount IS NULL) = (cost_currency IS NULL)),
  CONSTRAINT ck_intervention_chip
    CHECK (microchip_implanted IS NULL OR microchip_implanted ~ '^[0-9]{15}$')
);
CREATE INDEX idx_intervention_org_time  ON intervention (org_id, occurred_at DESC);
CREATE INDEX idx_intervention_animal    ON intervention (animal_id, occurred_at DESC);
CREATE INDEX idx_intervention_campaign  ON intervention (campaign_id, type)
  WHERE deleted_at IS NULL AND superseded_by_intervention_id IS NULL;
CREATE INDEX idx_intervention_mission   ON intervention (mission_id);

-- ALL reporting MUST read this view, never the base table (ADR-0018).
CREATE VIEW intervention_effective AS
  SELECT * FROM intervention
  WHERE deleted_at IS NULL
    AND superseded_by_intervention_id IS NULL;

-- ---------------------------------------------------------------------------
-- Media
-- ---------------------------------------------------------------------------

CREATE TABLE media (
  id                     uuid PRIMARY KEY,   -- client-generated UUIDv7
  org_id                 uuid NOT NULL REFERENCES org(id),
  storage_key            text NOT NULL,
  bucket                 text NOT NULL,
  variant                media_variant NOT NULL DEFAULT 'original',
  content_type           text NOT NULL,
  byte_size              bigint,
  sha256                 text,
  client_declared_sha256 text,
  width                  integer,
  height                 integer,
  captured_at            timestamptz,
  capture_location       geography(Point, 4326),
  uploaded_by_user_id    uuid REFERENCES app_user(id),
  status                 media_status NOT NULL DEFAULT 'pending',
  supersedes_media_id    uuid REFERENCES media(id),
  derivative_of_media_id uuid REFERENCES media(id),
  perceptual_hash        text,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  deleted_at             timestamptz,
  CONSTRAINT uq_media_storage_key UNIQUE (bucket, storage_key)
);
CREATE INDEX idx_media_org_status ON media (org_id, status) WHERE deleted_at IS NULL;
CREATE INDEX idx_media_unlinked ON media (created_at) WHERE status = 'processed';

CREATE TABLE media_link (
  id           uuid PRIMARY KEY,
  org_id       uuid NOT NULL REFERENCES org(id),
  media_id     uuid NOT NULL REFERENCES media(id),
  entity_type  media_entity_type NOT NULL,
  entity_id    uuid NOT NULL,
  role         media_role NOT NULL DEFAULT 'general',
  sort_order   integer NOT NULL DEFAULT 0,
  created_at   timestamptz NOT NULL DEFAULT now(),
  deleted_at   timestamptz,
  CONSTRAINT uq_media_link UNIQUE (media_id, entity_type, entity_id, role)
);
CREATE INDEX idx_media_link_entity ON media_link (entity_type, entity_id) WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- Audit — append-only, hash-chained per org (ADR-0014)
-- ---------------------------------------------------------------------------

CREATE TABLE audit_event (
  id             uuid PRIMARY KEY,
  org_id         uuid NOT NULL REFERENCES org(id),
  seq            bigint NOT NULL,
  occurred_at    timestamptz NOT NULL DEFAULT now(),
  actor_type     audit_actor_type NOT NULL,
  actor_user_id  uuid REFERENCES app_user(id),
  actor_device_id uuid REFERENCES device(id),
  action         text NOT NULL,
  entity_type    text NOT NULL,
  entity_id      uuid NOT NULL,
  diff           jsonb NOT NULL DEFAULT '{}'::jsonb,
  request_id     text,
  ip_hash        text,
  prev_hash      text,
  hash           text NOT NULL,
  chain_version  integer NOT NULL DEFAULT 1,
  CONSTRAINT uq_audit_event_org_seq UNIQUE (org_id, seq)
);
CREATE INDEX idx_audit_event_entity ON audit_event (org_id, entity_type, entity_id);
CREATE INDEX idx_audit_event_time   ON audit_event (org_id, occurred_at DESC);
CREATE INDEX idx_audit_event_actor  ON audit_event (actor_user_id, occurred_at DESC);

-- ---------------------------------------------------------------------------
-- Operational support
-- ---------------------------------------------------------------------------

CREATE TABLE idempotency_record (
  id               uuid PRIMARY KEY,
  org_id           uuid NOT NULL REFERENCES org(id),
  idempotency_key  text NOT NULL,
  endpoint         text NOT NULL,
  request_hash     text NOT NULL,
  response_status  integer,
  response_body    jsonb,
  created_at       timestamptz NOT NULL DEFAULT now(),
  expires_at       timestamptz NOT NULL,
  CONSTRAINT uq_idempotency UNIQUE (org_id, idempotency_key)
);
CREATE INDEX idx_idempotency_expiry ON idempotency_record (expires_at);

CREATE TABLE job_record (
  id             uuid PRIMARY KEY,
  org_id         uuid REFERENCES org(id),
  queue          text NOT NULL,
  job_key        text,
  status         job_status NOT NULL DEFAULT 'queued',
  progress       integer NOT NULL DEFAULT 0,
  attempts       integer NOT NULL DEFAULT 0,
  result         jsonb,
  error_detail   text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  started_at     timestamptz,
  finished_at    timestamptz
);
CREATE INDEX idx_job_record_org ON job_record (org_id, created_at DESC);
CREATE INDEX idx_job_record_status ON job_record (status, queue);

CREATE TABLE metric_snapshot (
  id            uuid PRIMARY KEY,
  org_id        uuid NOT NULL REFERENCES org(id),
  campaign_id   uuid REFERENCES campaign(id),
  metric_key    text NOT NULL,
  dimensions    jsonb NOT NULL DEFAULT '{}'::jsonb,
  value         numeric,
  period_start  timestamptz,
  period_end    timestamptz,
  computed_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_metric_snapshot
    UNIQUE (org_id, metric_key, dimensions, period_start, period_end)
);
CREATE INDEX idx_metric_snapshot_lookup ON metric_snapshot (org_id, metric_key, period_start);

CREATE TABLE report (
  id                  uuid PRIMARY KEY,
  org_id              uuid NOT NULL REFERENCES org(id),
  campaign_id         uuid REFERENCES campaign(id),
  kind                report_kind NOT NULL,
  params              jsonb NOT NULL DEFAULT '{}'::jsonb,
  locale              text NOT NULL DEFAULT 'ro',
  -- reproducibility anchors (FR-115, FR-116)
  snapshot_at         timestamptz NOT NULL,
  audit_head_hash     text,
  audit_head_seq      bigint,
  media_id            uuid REFERENCES media(id),
  artefact_sha256     text,
  status              job_status NOT NULL DEFAULT 'queued',
  generated_by_user_id uuid REFERENCES app_user(id),
  created_at          timestamptz NOT NULL DEFAULT now(),
  completed_at        timestamptz
);
CREATE INDEX idx_report_org ON report (org_id, created_at DESC);

COMMIT;

-- ---------------------------------------------------------------------------
-- Roles and grants (run once per environment, outside this transaction).
-- The application role MUST NOT be able to update or delete audit events
-- (FR-103, NFR-037). Migrations run as a separate, more privileged role.
--
--   CREATE ROLE tnr_app LOGIN PASSWORD '...';
--   GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO tnr_app;
--   REVOKE UPDATE, DELETE ON audit_event FROM tnr_app;
--   GRANT SELECT, INSERT ON audit_event TO tnr_app;
-- ---------------------------------------------------------------------------
