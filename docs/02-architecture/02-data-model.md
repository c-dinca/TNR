# Data model

The authoritative DDL is [`../../contracts/db/migrations/0001_init.sql`](../../contracts/db/migrations/0001_init.sql).
This document explains the *why*: relationships, invariants, lifecycles and the rules that SQL alone cannot
express. When the two disagree, the SQL wins and this document is wrong.

---

## 1. Global conventions

| Rule | Detail |
|---|---|
| Primary keys | `uuid`, UUIDv7 values. Generated **client-side** for offline-created records (`sighting`, `animal`, `intervention`, media) so identity is final before sync. Server-generated for server-only entities |
| Tenancy | Every tenant-scoped table has `org_id uuid NOT NULL REFERENCES org(id)`. No exceptions, no nullable tenancy |
| Timestamps | `timestamptz`, UTC, suffix `_at`. `created_at`/`updated_at` are server clocks; `occurred_at` is the client-observed event time and is never used for ordering |
| Soft delete | `deleted_at timestamptz NULL`. All queries filter it out. Hard delete only via GDPR erasure |
| Geometry | `geography(Point, 4326)` for locations; `geography(Polygon, 4326)` for areas. Never loose lat/lng columns |
| Enums | Postgres native enums for closed domains that rarely change; `text` + check constraint where values will grow |
| Money | `numeric(12,2)` plus `currency char(3)`. Never floats |
| Naming | tables singular (`sighting`), columns `snake_case`, FKs `<entity>_id`, indexes `idx_<table>_<cols>`, constraints `ck_`/`uq_`/`fk_` |
| Migrations | forward-only numbered SQL files, never edited after being applied anywhere |

## 2. Entity relationship overview

```
org ──┬── membership ──── user
      │
      ├── invitation
      ├── vehicle ─────────────┐
      ├── campaign ──┬─────────┼──── grant (optional)
      │              │         │
      ├── pack ──┬───┼── mission ── mission_stop
      │          │   │       │            │
      │          │   │       └────────────┤
      │          │   │                    │
      ├── sighting ──┴── sighting_pack    │
      │     │                             │
      ├── animal ── animal_pack           │
      │     │                             │
      ├── intervention ◀───────────────────┘  (optional mission/stop link)
      │     │
      ├── media ── media_link (polymorphic attach)
      ├── audit_event         (hash-chained per org)
      ├── idempotency_record
      ├── job_record          (async job visibility)
      ├── metric_snapshot     (dashboard projections)
      ├── report              (generated artefacts)
      └── device              (Phase 2 seam, minimal)
```

## 3. Core entities

### 3.1 `org`

The tenant. Holds display name, country (default `RO`), default locale, timezone, subscription tier and soft
limits, and the **audit chain head** (`audit_head_hash`, `audit_head_seq`) used to append the next event.

*Invariants*
- An org always has at least one `owner` membership (`FR-015`).
- `audit_head_*` is updated only by the audit append routine, inside the same transaction as the change.

### 3.2 `user` and `membership`

`user` is global (identity), `membership` is tenant-scoped (authorisation). A user can hold memberships in
several orgs (`FR-009`); permissions **always** derive from the membership for the active org, never from the
user.

`role`: `owner | admin | coordinator | vet | volunteer | funder` (`FR-017`).

*Invariants*
- `uq_membership_user_org` — one membership per (user, org).
- A `funder` membership requires at least one `funder_campaign_grant` row; a funder with no grants sees nothing.
- Deactivating a membership revokes sessions scoped to that org within one access-token lifetime.

### 3.3 `sighting`

The atomic field observation. Highest-volume table.

Key columns: `location geography(Point,4326)`, `location_accuracy_m`, `occurred_at`, `animal_count_estimate`,
`notched_count_observed`, `health_note`, `reported_by_user_id`, `source` (`field_app | import | device`),
`device_id` (Phase 2), `client_created_at`, `clock_skew_ms`, `status` (`active | duplicate | rejected`).

*Invariants*
- Immutable after insert except `status`, `deleted_at`, and pack linkage (`FR-036`).
- `occurred_at` ≤ `created_at + 24h`, rejected otherwise (`FR-035`).
- `notched_count_observed` ≤ `animal_count_estimate`.
- `source = 'device'` requires `device_id` — the Phase 2 seam.

*Indexes*: GIST on `location`; `(org_id, occurred_at desc)`; `(org_id, status)` partial where not deleted.

### 3.4 `pack`

The planning unit: a persistent cluster of animals in one territory.

Key columns: `name`, `centroid geography(Point,4326)`, `area geography(Polygon,4326)` (nullable),
`animal_count_estimate`, `estimate_method` (`field_report | max_observed | mean_recent | manual`),
`notched_ratio_observed`, `status` (`proposed | active | closed`), `closed_reason`
(`resolved | relocated | duplicate | erroneous`), `merged_into_pack_id`, `locality_id`.

*Invariants*
- `status = 'closed'` requires `closed_reason` (`FR-044`).
- `merged_into_pack_id` set ⟹ status `closed` with reason `duplicate`; the merged pack is retained forever for
  audit, never deleted.
- `centroid` is derived from recent linked sightings and recomputed by the clustering job; a coordinator's
  manual centroid sets `centroid_is_manual = true` and the job then leaves it alone.
- Merge and split write audit events listing every affected sighting id (`FR-043`).

### 3.5 `sighting_pack`

Many-to-many, because clustering is revisable and history must survive a re-decision. Carries
`linked_by` (`auto | manual`), `linked_at`, `confidence`, `unlinked_at`.

Unlinking sets `unlinked_at` rather than deleting the row — this is how a merge stays reversible for 30 days
(`FR-042`, `NFR-063`).

### 3.6 `animal`

An individual dog. Identification is deliberately weak-by-default: most field animals have no chip.

Key columns: `microchip` (15 digits, nullable), `microchip_country_prefix`, `is_romanian_chip`, `name`, `sex`,
`estimated_birth_year`, `size_class`, `coat_description`, `ear_notch_status`
(`unknown | none | left | right | both`), `is_owned`, `household_ref`, `sterilisation_status`
(`unknown | reported_sterilised | confirmed_sterilised | not_sterilised`), `chip_lookup_*`.

*Invariants*
- `uq_animal_microchip_org` — unique per org where not null (`FR-052`).
- `ck_animal_microchip_format` — exactly 15 digits (`FR-051`). Non-`642` prefixes are valid and set
  `is_romanian_chip = false`.
- `sterilisation_status` is **derived from interventions** and written only by the domain service.
  `reported_sterilised` is the sole value settable from a field observation, and never overrides
  `confirmed_sterilised` (`FR-058`).
- `is_owned = true` may carry `household_ref` (a free label such as "Casa 12, Str. Principală") but **no owner
  personal data** (`FR-057`) — see the GDPR doc for why.

### 3.7 `animal_pack`

Temporal membership: `valid_from`, `valid_to`. An animal has at most one open row. This gives point-in-time pack
composition for coverage reporting (`FR-047`, `FR-053`).

### 3.8 `intervention`

**The most important table in the system.** It is the billable unit, the reportable unit and the audited unit.

Key columns: `animal_id`, `type` (`sterilisation | vaccination_rabies | microchip_implant | treatment |
examination | euthanasia`), `occurred_at`, `performed_by_user_id`, `performed_by_vet_name`, `vet_licence_ref`,
`mission_id`, `mission_stop_id`, `campaign_id`, `location`, `anaesthesia_note`, `complication_note`,
`ear_notch_applied`, `microchip_implanted`, `cost_amount`, `cost_currency`, `supersedes_intervention_id`,
`superseded_by_intervention_id`, `justification` (required for euthanasia).

*Invariants — enforced in the service layer and, where possible, in SQL*
- **Append-only** (`FR-093`). No `UPDATE` except setting `superseded_by_intervention_id` and `deleted_at`.
  Corrections insert a new row with `supersedes_intervention_id`.
- `type = 'euthanasia'` requires `performed_by_vet_name` and non-empty `justification` (`FR-095`). The UI must
  never present it as a population-control option.
- `type = 'microchip_implant'` requires the animal to have a `microchip`.
- `type = 'sterilisation'` transitions the animal to `confirmed_sterilised` and may set `ear_notch_applied`.
- A superseded intervention is excluded from all reporting aggregates; both rows are retained.
- Every insert writes an audit event in the same transaction (`FR-102`).

*Reporting view*: `intervention_effective` — non-deleted, non-superseded rows only. **All reporting must read
this view**, never the base table. This single rule prevents the most likely reporting bug in the product.

### 3.9 `vehicle`, `mission`, `mission_stop`

`vehicle`: label, plate, `cage_capacity`, `is_mobile_clinic`, `is_active`, `home_depot` point.

`mission`: `scheduled_date`, `vehicle_id`, `campaign_id`, `status`
(`draft | planned | in_progress | completed | cancelled`), `depot_start`, `depot_end`,
`window_start_at`, `window_end_at`, `planned_distance_m`, `planned_duration_s`, `actual_distance_m`,
`actual_duration_s`, `optimisation_engine`, `optimisation_version`, `optimisation_mode`
(`optimised | fallback_straight_line | manual`), `optimised_at`.

`mission_stop`: `mission_id`, `sequence`, `pack_id` (nullable), `location`, `stop_type`
(`pack | clinic | depot | fuel | handover`), `eta_at`, `arrived_at`, `completed_at`, `outcome`
(`pending | arrived | completed | skipped`), `skip_reason`, `animals_captured`, `outcome_location`,
`outcome_recorded_offline`.

*Invariants*
- `uq_mission_stop_sequence` on `(mission_id, sequence)` where not deleted.
- Status transitions enforced server-side (`FR-083`): `draft → planned → in_progress → completed`, with
  `cancelled` reachable from any non-`completed` state. Illegal transitions return `409`.
- Sum of `animals_captured` across stops must not exceed vehicle `cage_capacity` without an override flag.
- `actual_*` stay NULL until derivable; they are **never** defaulted to zero (`FR-080`).
- A mission with `optimisation_mode = 'fallback_straight_line'` must be labelled as such in every UI surface.

### 3.10 `campaign` and `grant`

`campaign`: name, `starts_on`, `ends_on`, `target_intervention_count`, `budget_amount`, `budget_currency`,
`grant_id`, `scope_area geography(Polygon,4326)`, `status`.

`grant`: `donor_name`, `reference`, `reporting_period_start/end`, `required_metrics jsonb`, `contact_email`.

`funder_campaign_grant`: the explicit access grant that lets a `funder` membership read one campaign's reports
and nothing else (`FR-016`).

### 3.11 `media` and `media_link`

`media`: `storage_key`, `bucket`, `content_type`, `byte_size`, `sha256`, `client_declared_sha256`,
`width`, `height`, `captured_at` (from EXIF), `capture_location`, `uploaded_by_user_id`, `status`
(`pending | uploaded | processed | quarantined | failed`), `supersedes_media_id`, `derivative_of_media_id`,
`variant` (`original | web | thumb`).

`media_link`: polymorphic attachment — `media_id`, `entity_type` (`sighting | intervention | animal | pack`),
`entity_id`, `role` (`general | before | after | evidence`), `sort_order`.

*Invariants*
- Immutable bytes (`FR-062`). A replacement is a new `media` row with `supersedes_media_id`.
- `sha256` computed server-side at finalisation and compared to `client_declared_sha256`; mismatch ⟹
  `quarantined` + alert (`FR-061`).
- EXIF is preserved on `original`, stripped on derivatives (`FR-063`).
- A `media` row with no `media_link` after 48 h is garbage-collected and logged (`FR-067`).

Polymorphic linkage is a deliberate trade-off: it costs referential integrity on `entity_id` (validated in the
service layer, plus a nightly consistency check) and buys a single upload/evidence pipeline instead of four.

### 3.12 `audit_event`

Append-only, hash-chained per org.

Columns: `org_id`, `seq bigint`, `occurred_at`, `actor_user_id`, `actor_type` (`user | system | device`),
`action`, `entity_type`, `entity_id`, `diff jsonb`, `request_id`, `ip_hash`, `prev_hash`, `hash`,
`chain_version`.

Hashing (canonical, stable, documented so third parties can verify):

```
hash = SHA256( chain_version || org_id || seq || occurred_at(RFC3339 UTC, µs) ||
               actor_type || coalesce(actor_user_id,'-') || action ||
               entity_type || entity_id || canonical_json(diff) || coalesce(prev_hash,'GENESIS') )
```

`canonical_json` = keys sorted lexicographically, no insignificant whitespace, UTF-8, numbers in shortest
round-trip form. Any change to this function requires a `chain_version` bump and an ADR — it is a published
verification contract, not an implementation detail.

*Invariants*
- No `UPDATE` or `DELETE` path exists in any repository. Enforced by a DB role lacking those grants on this
  table (`FR-103`, `NFR-037`).
- `uq_audit_event_org_seq` on `(org_id, seq)`; sequence allocated by `SELECT ... FOR UPDATE` on the org row,
  which also serialises chain appends per org.
- Written in the same transaction as its change (`FR-102`). If the audit write fails, the change rolls back.

Per-org serialisation is a known write-throughput ceiling. It is acceptable: a busy org writes tens of events
per minute, not thousands per second. Revisit only with measured contention.

### 3.13 `idempotency_record`

`org_id`, `idempotency_key`, `endpoint`, `request_hash`, `response_status`, `response_body jsonb`,
`created_at`, `expires_at` (24 h).

Same key + same request hash ⟹ replay the stored response. Same key + different request hash ⟹ `409` (`FR-034`).
Unique on `(org_id, idempotency_key)`.

### 3.14 `job_record`, `metric_snapshot`, `report`

`job_record` mirrors BullMQ state into Postgres so the UI can show honest async status (`NFR-064`) and so
failures survive a Redis flush.

`metric_snapshot` holds dashboard projections: `org_id`, `campaign_id`, `metric_key`, `dimensions jsonb`,
`value numeric`, `period_start`, `period_end`, `computed_at`. Fully rebuildable from source
(`FR-112`).

`report`: `campaign_id`, `kind` (`donor_pdf | evidence_pack | recs_csv`), `params jsonb`, `locale`,
`snapshot_at`, `audit_head_hash`, `media_id` (the artefact), `status`, `generated_by_user_id`. Storing
`snapshot_at` + `audit_head_hash` is what makes a report reproducible and verifiable (`FR-115`, `FR-116`).

### 3.15 `device` — Phase 2 seam

Minimal now: `org_id`, `hardware_id`, `label`, `kind` (`trap_sensor`), `status`,
`credential_hash`, `last_seen_at`, `firmware_version`, `assigned_pack_id`.

Phase 1 builds the table, the `source = 'device'` path on `sighting`, and `actor_type = 'device'` in the audit
log. It builds **no** device UI, no MQTT bridge, no provisioning flow. Rationale in
[`12-phase-2-iot-seams.md`](12-phase-2-iot-seams.md).

### 3.16 `locality`

Reference data (not tenant-scoped): Romanian administrative units — `siruta_code`, `name`, `county`, `type`,
`geometry geography(MultiPolygon,4326)`, `population_estimate`, `dog_population_estimate`.

Used for coverage choropleths and for aggregating funder-visible geography so precise pack locations never leave
the org (`FR-031`, `FR-119`). Loaded from open data by a seed script; a nightly job assigns `locality_id` to
packs by spatial containment.

## 4. Lifecycle state machines

**Pack**
```
proposed ──confirm──▶ active ──close(reason)──▶ closed
   └──────reject──────────────────────────────▶ closed(erroneous)
active ──merge into other──▶ closed(duplicate)   [merged_into_pack_id set]
```

**Mission** — `draft → planned → in_progress → completed`; `cancelled` from any non-completed state.
Re-optimisation permitted in `draft`/`planned`; in `in_progress` only with explicit confirmation, preserving
completed stops.

**Mission stop** — `pending → arrived → completed`, or `pending → skipped(reason)`.

**Media** — `pending → uploaded → processed`; `→ quarantined` on hash mismatch or type violation;
`→ failed` on terminal processing error.

**Animal sterilisation status**
```
unknown ──field observation──▶ reported_sterilised
unknown/reported ──sterilisation intervention──▶ confirmed_sterilised   [terminal]
unknown ──vet examination finds intact──▶ not_sterilised
```
`confirmed_sterilised` is terminal and can never be downgraded by a field report. Coverage numbers count only
`confirmed_sterilised`, which is precisely why the field-reported value must stay separable.

## 5. Cross-cutting query rules

1. Every tenant query filters `org_id` and `deleted_at IS NULL`. Repositories take an `OrgContext` as their
   first argument; there is no way to construct a tenant query without one.
2. Reporting reads `intervention_effective`, never `intervention`.
3. Spatial filters use `ST_DWithin(location, :point, :metres)` on `geography` — index-usable. Never
   `ST_Distance(...) < x`, which is not.
4. Viewport queries are bounded and clustered above the feature cap (`FR-038`, `NFR-008`).
5. Timestamp ordering uses server `created_at` or `seq`. `occurred_at` is display and evidence only
   (`NFR-018`).

## 6. Indexing strategy

| Table | Index | Serves |
|---|---|---|
| `sighting` | GIST (`location`) | proximity, viewport |
| `sighting` | (`org_id`, `occurred_at` desc) | recent-activity lists |
| `sighting` | (`org_id`, `status`) partial `deleted_at IS NULL` | moderation queue |
| `pack` | GIST (`centroid`) | map, clustering |
| `pack` | (`org_id`, `status`) | console lists |
| `animal` | unique (`org_id`, `microchip`) where not null | chip conflict detection |
| `intervention` | (`org_id`, `occurred_at` desc) | reporting time series |
| `intervention` | (`animal_id`, `occurred_at` desc) | animal history |
| `intervention` | (`campaign_id`, `type`) partial effective-only | dashboard aggregates |
| `mission_stop` | (`mission_id`, `sequence`) | execution order |
| `audit_event` | unique (`org_id`, `seq`) | chain integrity |
| `audit_event` | (`org_id`, `entity_type`, `entity_id`) | per-record history |
| `media_link` | (`entity_type`, `entity_id`) | evidence assembly |
| `locality` | GIST (`geometry`) | containment assignment |

Add no other index without a measured query to justify it; each one taxes the write path that field sync
depends on.

## 7. Multi-tenancy: why not RLS

Postgres row-level security was considered and deferred (ADR-0016). Application-layer scoping was chosen because
the same domain services run in workers with a system identity, RLS policy debugging is opaque, and our
adversarial cross-tenant test suite (`NFR-030`) gives comparable assurance with far better diagnostics. RLS
remains a viable defence-in-depth addition later; the schema (uniform `org_id`) is deliberately shaped so it can
be added without migration.

## 8. Open questions

> **OQ-DM-1** — Should `sighting` be partitioned by month from the start? *Deferred*: 500k rows is nothing for
> Postgres. Revisit at 5M rows or when index bloat is measured.

> **OQ-DM-2** — Do we need a `species` column for cat TNR? *Deferred*: modelled implicitly as dogs. Adding
> `species` later is additive with a default, so the cost of waiting is near zero.

> **OQ-DM-3** — Dog-population estimates per locality: source and licence? Needed for the coverage choropleth
> (`FR-119`). Blocks `TNR-095`; must be resolved before that item starts.
