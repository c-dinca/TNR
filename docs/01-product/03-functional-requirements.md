# Functional requirements

Numbered, testable requirements. **Identifiers are permanent** — never renumber; mark withdrawn instead. Each
requirement must be traceable to at least one automated test. `MUST` / `SHOULD` / `MAY` are RFC 2119.

Numbering blocks: 001–019 identity · 020–039 capture & tenancy · 040–059 packs & animals · 060–069 media ·
070–089 missions · 090–109 interventions & audit · 110–119 reporting · 120–129 compliance.

---

## Identity and access (001–019)

| ID | Requirement |
|---|---|
| FR-001 | The system MUST allow self-service registration creating a `user`, an `org`, and an `owner` `membership` atomically. |
| FR-002 | Passwords MUST be ≥ 12 characters, checked against a common-password list, hashed with Argon2id, and never logged. |
| FR-003 | Login MUST issue a short-lived access token (≤ 15 min) and a rotating refresh token (≤ 90 days). |
| FR-004 | Refresh token reuse MUST be detected; on detection the whole token family MUST be revoked and an audit event written. |
| FR-005 | Authentication and registration responses MUST NOT disclose whether an email is registered. |
| FR-006 | Logout MUST revoke the presented refresh token server-side, and MUST warn the client if a local outbox is non-empty. |
| FR-007 | The system MUST support password reset by emailed single-use token valid ≤ 60 minutes. |
| FR-008 | Failed login attempts MUST be rate-limited per account and per IP with exponential backoff. |
| FR-009 | A user MUST be able to hold memberships in multiple orgs and switch the active org without re-authenticating. |
| FR-010 | All identity mutations MUST write audit events. |
| FR-011 | An `owner` or `admin` MUST be able to invite a user by email with a specified role. |
| FR-012 | An invitation MUST be single-use, expire in ≤ 14 days, and be revocable before acceptance. |
| FR-013 | Accepting an invitation MUST create a `membership` with exactly the invited role, no more. |
| FR-014 | Re-inviting an existing member MUST be idempotent and MUST NOT alter the existing role. |
| FR-015 | An `owner` MUST be able to change or revoke any membership except the last remaining `owner`. |
| FR-016 | The system MUST support a `funder` role limited to reports, metrics and evidence packs for explicitly granted campaigns. |
| FR-017 | Roles MUST be `owner`, `admin`, `coordinator`, `vet`, `volunteer`, `funder`. Permissions per role are defined in the auth doc and enforced in the service layer. |
| FR-018 | Every authorisation denial MUST return an RFC 9457 problem document and MUST be logged with actor, resource and required permission. |
| FR-019 | Sessions MUST be listable and individually revocable by their owner. |

## Field capture and tenancy (020–039)

| ID | Requirement |
|---|---|
| FR-020 | A user with `sighting:create` MUST be able to create a `sighting` with location, `occurred_at` and estimated animal count as the only required fields. |
| FR-021 | Sighting location MUST be captured as WGS84 (EPSG:4326) with recorded horizontal accuracy in metres, and MUST be manually adjustable on a map. |
| FR-022 | A sighting MUST accept up to 5 photos; media upload MUST be independent of sighting creation. |
| FR-023 | Client-side image processing MUST downscale to ≤ 1600 px long edge and ≤ 500 KB before queueing, preserving original EXIF capture time and GPS in metadata. |
| FR-024 | Sighting creation MUST succeed with no network connectivity, storing the record locally with a client-generated UUIDv7 primary key. |
| FR-025 | The client MUST maintain a durable outbox surviving app restart and device reboot. |
| FR-026 | Outbox replay MUST be idempotent: replaying an identical mutation MUST NOT create a duplicate server record. |
| FR-027 | The client MUST display pending, syncing and failed counts distinctly, with a reason and manual retry for failures. |
| FR-028 | A sighting MUST allow recording the number of visibly ear-notched animals observed. |
| FR-029 | The client SHOULD cache basemap tiles for a bounded operating region for offline map rendering. |
| FR-030 | Every tenant-scoped query MUST filter by the `org_id` resolved from the authenticated session; `org_id` MUST NEVER be taken from a request body. |
| FR-031 | Precise pack and sighting geometry MUST NOT be exposed to `funder` users or any unauthenticated surface; funder-visible geography MUST be aggregated to at least locality level. |
| FR-032 | Attempted cross-org access MUST return `404` for existence-revealing reads and `403` for permission failures on known-visible resources, and MUST be logged. |
| FR-033 | Bulk export endpoints MUST be restricted to `admin`/`owner` and MUST be audit-logged with row counts. |
| FR-034 | The API MUST accept `Idempotency-Key` on all mutating requests and MUST return the original response for a repeated key within 24 hours. |
| FR-035 | The API MUST distinguish `occurred_at` (client-observed) from `created_at` (server-received) on all field-captured records and MUST reject `occurred_at` more than 24 h in the future. |
| FR-036 | Sightings MUST be immutable after sync except for moderation fields (`status`, `merged_into_pack_id`, `deleted_at`). |
| FR-037 | The system MUST support cursor-based pagination on all list endpoints with a maximum page size of 200. |
| FR-038 | List endpoints for spatial data MUST support a bounding-box filter and MUST cap returned features, providing a clustered representation above the cap. |
| FR-039 | The client MUST function on the two most recent major versions of Chrome for Android, Safari iOS and desktop Chrome/Firefox/Safari. |

## Packs and animals (040–059)

| ID | Requirement |
|---|---|
| FR-040 | On sighting sync, the system MUST asynchronously evaluate pack association within a configurable radius (default 300 m) and time window (default 90 days). |
| FR-041 | A sighting matching an existing pack MUST be attached as evidence; otherwise a candidate pack MUST be proposed with status `proposed`. |
| FR-042 | All automatic clustering decisions MUST be visible to coordinators and reversible without data loss. |
| FR-043 | Coordinators MUST be able to merge, split, rename, and close packs; every operation MUST write an audit event capturing affected sighting IDs. |
| FR-044 | Closing a pack MUST require a reason from `resolved`, `relocated`, `duplicate`, `erroneous`. |
| FR-045 | Packs MUST expose an observed notched ratio, and route planning MUST support deprioritising packs above a configurable threshold. |
| FR-046 | A pack MUST maintain a representative location (centroid of recent sightings) and an estimated animal count with a recorded derivation method. |
| FR-047 | Pack history MUST be queryable as of a past date for coverage reporting. |
| FR-050 | An `animal` MUST be creatable with identification by microchip, by ear-notch plus description, or by description only. |
| FR-051 | Microchip numbers MUST be validated as exactly 15 numeric digits; a `642` prefix marks Romanian registration, other prefixes MUST be accepted and flagged non-Romanian. |
| FR-052 | Microchip numbers MUST be unique within an org; a conflicting entry MUST be rejected with a reference to the existing animal. |
| FR-053 | An animal's pack membership MUST be changeable over time while preserving full history. |
| FR-054 | Microchip registry lookup MUST be asynchronous, cached, per-provider rate-limited, and MUST NOT block or fail animal creation. |
| FR-055 | Lookup results MUST record provider, timestamp and raw response, and MUST be labelled as unofficial and non-authoritative in the UI. |
| FR-056 | The system MUST provide a date-ranged CSV export of interventions in the column order required for RECS entry. |
| FR-057 | The system MUST record whether an animal is owned, and MUST support a household reference for owned yard dogs without requiring owner personal data. |
| FR-058 | Animal sterilisation status MUST be derived from interventions, never set directly, except for an explicitly flagged `reported_by_field` value. |

## Media (060–069)

| ID | Requirement |
|---|---|
| FR-060 | Media upload MUST use short-lived presigned URLs directly to object storage; media bytes MUST NOT transit the API. |
| FR-061 | Every media object MUST store a SHA-256 content hash computed server-side on finalisation and compared against a client-declared hash. |
| FR-062 | Media MUST be immutable; replacement MUST create a new version and retain the prior one. |
| FR-063 | The system MUST generate thumbnail and web-size derivatives asynchronously, and MUST strip EXIF from derivatives while preserving originals. |
| FR-064 | Media originals MUST retain capture time and GPS where present, and these MUST be shown in the evidence view alongside the content hash. |
| FR-065 | Media served to clients MUST use signed URLs expiring in ≤ 15 minutes. |
| FR-066 | Uploads MUST be virus/type-scanned to the extent of validating magic bytes against declared MIME, rejecting anything not in an allowlist of image types. |
| FR-067 | Orphaned media (no owning record after 48 h) MUST be garbage-collected, and the collection MUST be logged. |

## Missions and routing (070–089)

| ID | Requirement |
|---|---|
| FR-070 | Coordinators MUST be able to create a `mission` for a date, a `vehicle` and one or more `stop`s derived from packs or arbitrary points. |
| FR-071 | Mission creation MUST warn when a selected pack is already targeted by another mission within the same date window, without blocking. |
| FR-072 | Missions MUST be visible to assigned members and to coordinators of the same org, and to nobody else. |
| FR-073 | The system MUST compute an optimised stop order minimising travel duration, honouring a depot start/end, a mission time window, and vehicle cage capacity. |
| FR-074 | Optimisation MUST return total distance, total duration, per-stop ETA, and the engine/version used. |
| FR-075 | If the routing engine is unavailable, the system MUST offer a clearly labelled straight-line nearest-neighbour ordering. |
| FR-076 | Manual stop reordering MUST be supported and MUST NOT be overwritten by re-optimisation without explicit confirmation. |
| FR-077 | Opening a mission while online MUST cache all data required for offline execution: stops, pack details, notes, and corridor map tiles. |
| FR-078 | Each stop MUST support outcomes `arrived`, `completed`, `skipped` with a reason, and a count of animals captured, all recordable offline. |
| FR-079 | Stop outcome timestamps MUST preserve field-observed time and MUST record the device location at the time of the outcome where available. |
| FR-080 | Mission detail MUST show planned vs. actual distance and duration; unknown actuals MUST be displayed as unknown, never zero. |
| FR-081 | Campaign summaries MUST aggregate planned vs. actual distance across missions. |
| FR-082 | A vehicle MUST record cage capacity and MUST NOT be double-booked for overlapping missions without a warning. |
| FR-083 | Missions MUST have lifecycle states `draft`, `planned`, `in_progress`, `completed`, `cancelled`, with transitions enforced server-side. |

## Interventions and audit (090–109)

| ID | Requirement |
|---|---|
| FR-090 | A `vet` or `coordinator` MUST be able to record an `intervention` with animal, type, `occurred_at` and performing veterinarian as required fields. |
| FR-091 | Intervention types MUST include `sterilisation`, `vaccination_rabies`, `microchip_implant`, `treatment`, `examination`, `euthanasia`. |
| FR-092 | Interventions MUST be creatable offline and MUST validate microchip format locally before queueing. |
| FR-093 | Interventions MUST be append-only after sync: a correction MUST create a new record referencing and superseding the original, and both MUST be retained. |
| FR-094 | Interventions MUST support before/after photo evidence with content hashes, capture times and uploader identity. |
| FR-095 | `euthanasia` MUST require an attesting veterinarian and a free-text medical justification, and MUST NOT be selectable as a population-control outcome. |
| FR-096 | Interventions MAY record a cost with currency, used for cost-per-intervention reporting. |
| FR-097 | An intervention MUST be linkable to a mission, a stop and a campaign. |
| FR-098 | Recording a `sterilisation` MUST update the animal's derived sterilisation status and MUST support recording that an ear-notch was applied. |
| FR-100 | Every create, update and soft delete of a domain record MUST write an audit event with actor, org, timestamp, resource, action, and a before/after diff. |
| FR-101 | Audit events MUST be hash-chained per org: each event stores the hash of the previous event's canonical form. |
| FR-102 | Audit events MUST be written in the same database transaction as the change they describe. |
| FR-103 | Audit events MUST NOT be updatable or deletable through any application role or endpoint. |
| FR-104 | Data exports and report generations MUST write audit events including parameters and row counts. |
| FR-105 | The system MUST expose an endpoint that verifies a chain segment and reports the first broken link if any. |
| FR-106 | Authentication events (login, failure, token reuse, permission denial) MUST be audit-logged. |

## Reporting (110–119)

| ID | Requirement |
|---|---|
| FR-110 | The system MUST provide a campaign dashboard with interventions by type over time, packs identified vs. covered, coverage estimate by locality, and active missions. |
| FR-111 | Every displayed aggregate MUST be drillable to the underlying records. |
| FR-112 | Dashboard aggregates MUST be computed from a materialised or cached projection refreshed at most 5 minutes behind, with the freshness timestamp shown. |
| FR-113 | The system MUST generate a donor report PDF for a campaign and date range in Romanian, English or German. |
| FR-114 | The report MUST include intervention counts by type and locality, cost per intervention where costs exist, coverage change over the period, a map, and a sample of evidence. |
| FR-115 | Report generation MUST be asynchronous with a status and a download link, and MUST be reproducible byte-for-byte for the same data snapshot and parameters. |
| FR-116 | Reports MUST state the data snapshot time and the audit-chain head hash at generation time. |
| FR-117 | The system MUST produce an evidence pack archive containing the PDF, a media manifest with hashes, interventions CSV, and an audit-chain excerpt. |
| FR-118 | The evidence pack MUST include instructions enabling third-party verification of hashes without TNR-OS software, and the pack's own hash MUST be recorded in the audit log. |
| FR-119 | The system SHOULD render a coverage choropleth by administrative unit, visually distinguishing "no data" from "zero coverage". |

## Compliance (120–129)

| ID | Requirement |
|---|---|
| FR-120 | The system MUST provide per-user data export in a machine-readable format on request. |
| FR-121 | The system MUST provide erasure that removes personal identifiers while retaining anonymised operational records required for donor audit, recording the legal basis. |
| FR-122 | DSR operations MUST require `owner`/`admin` plus explicit confirmation, and MUST be audit-logged. |
| FR-123 | Data retention periods MUST be configurable per data class and enforced by a scheduled job that logs its actions. |
| FR-124 | All personal data MUST be stored and processed in EU regions only. |
| FR-125 | The system MUST maintain a record of processing activities sufficient for GDPR Article 30, kept in the security doc. |
| FR-126 | Users MUST be able to see which orgs and roles they hold, and to leave an org unless they are its last `owner`. |

---

## Withdrawn requirements

None yet. When withdrawing, keep the row and set the text to `WITHDRAWN (ADR-XXXX): reason`.
