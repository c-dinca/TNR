# Backlog

**The work queue.** An agent does not start work that is not an item here.

Each item declares:

- **Reading** — the docs to read. Read these, not all of `docs/`.
- **Touches** — the paths it may modify. If another in-progress item overlaps, stop and report (`AGENTS.md` §3).
- **Role** — which agent role owns it (`AGENTS.md` §9).
- **AC** — acceptance criteria. All must be demonstrably true.
- **Blocks / Blocked by** — sequencing.

Status values: `todo`, `in-progress`, `review`, `done`, `blocked`. Update status in this file as part of the PR.

Everything below is `todo`.

---

# M0 — Foundation

### TNR-001 · Monorepo scaffold · role `infra`
Create the workspace exactly as specified: pnpm workspaces, Turborepo, shared tsconfig/eslint/prettier presets, the
`apps/` and `packages/` skeletons, root scripts.

- **Reading**: `04-engineering/01-repo-structure.md`, ADR-0001, ADR-0002
- **Touches**: root config files, `packages/config/**`, empty package skeletons
- **AC**: `pnpm install`, `pnpm lint`, `pnpm typecheck`, `pnpm build` all succeed on an empty project; boundary
  lint rules are configured and a deliberate violation fails; Node 22 and pnpm 9 are pinned.
- **Blocks**: everything

### TNR-002 · Local infrastructure with Docker Compose · role `infra`
Postgres+PostGIS 16-3.4, Redis, MinIO, Mailpit. Bucket creation on first run.

- **Reading**: `04-engineering/02-local-dev-setup.md`, `02-architecture/09-infrastructure-and-devops.md`
- **Touches**: `infra/compose/**`, `infra/scripts/**`, `.env.example`
- **AC**: `pnpm infra:up` brings all services healthy; `SELECT postgis_version()` works; MinIO has the media
  bucket; Mailpit receives mail. **Resolve OQ-INFRA-1** (managed Postgres provider) and record it in an ADR.

### TNR-003 · Initial database migration · role `api`
Apply `contracts/db/migrations/0001_init.sql`; build the migration runner.

- **Reading**: `02-architecture/02-data-model.md`, ADR-0005, ADR-0014, ADR-0015, `contracts/db/migrations/0001_init.sql`
- **Touches**: `packages/db/**`, `contracts/db/migrations/**`
- **AC**: migration applies cleanly to an empty database and is idempotent to re-run detection; all tables,
  enums, indexes and the `intervention_effective` view exist; the `tnr_app` role has no `UPDATE`/`DELETE` on
  `audit_event`; a replay-from-scratch test passes.
- **Blocked by**: TNR-002

### TNR-004 · Drizzle schema and repository base · role `api`
Drizzle schema mirroring the migration, custom `geography` column type, `OrgContext`, base repository, unit of
work.

- **Reading**: `02-architecture/02-data-model.md` §5, ADR-0005, ADR-0016
- **Touches**: `packages/db/**`
- **AC**: a repository method cannot be written without `OrgContext` (type-level); the `geography` type round-trips
  a point; a schema-drift check compares Drizzle to the migrated database and fails on divergence.
- **Blocked by**: TNR-003

### TNR-005 · API skeleton with global cross-cutting concerns · role `api`
NestJS on Fastify with `OrgScopeGuard`, `PermissionsGuard`, `IdempotencyInterceptor`, `AuditInterceptor`,
`ProblemJsonExceptionFilter`, Zod validation pipe, env schema, request-id propagation, `/healthz` and `/readyz`.

- **Reading**: `02-architecture/01-system-overview.md` §4, `02-architecture/03-api-design.md`, ADR-0003
- **Touches**: `apps/api/src/main.ts`, `apps/api/src/app.module.ts`, `apps/api/src/common/**`, `apps/api/src/config/**`
- **AC**: an unhandled error returns a valid problem document with a `request_id`; a missing env var crashes at
  boot; `/healthz` returns the commit SHA and does not touch the database; the idempotency interceptor replays a
  stored response for a repeated key.
- **Blocked by**: TNR-004

### TNR-006 · Web app shell · role `web`
Vite + React 19 + TypeScript, routing split `/f` (field) and `/c` (console), Tailwind + the UI package, i18n with
`ro`/`en`, PWA manifest and service-worker registration.

- **Reading**: `02-architecture/01-system-overview.md` §6, `01-product/01-scope-and-personas.md`, `04-engineering/03-coding-standards.md` §6
- **Touches**: `apps/web/**`, `packages/ui/**`
- **AC**: both route trees render; field mode is a separate lazy chunk; the bundle-composition check fails if field
  mode imports a chart/grid/PDF library; the app is installable; a missing i18n key fails CI.

### TNR-007 · Shared package foundations · role `shared`
Zod schemas for primitives (Point, timestamps, UUIDv7, microchip), permission constants, error slugs, limits, the
OpenAPI type generator.

- **Reading**: `04-engineering/01-repo-structure.md` §5, `02-architecture/03-api-design.md`
- **Touches**: `packages/shared/**`
- **AC**: no runtime dependency beyond Zod; the package imports cleanly in Node, browser and service-worker
  contexts; `pnpm contracts:gen` produces types from `contracts/openapi.yaml`; a point schema rejects a
  latitude-first pair outside valid longitude range.

### TNR-008 · CI pipeline · role `infra`
The PR gate exactly as specified.

- **Reading**: `04-engineering/06-ci-cd.md`, `04-engineering/04-testing-strategy.md`
- **Touches**: `.github/workflows/**`
- **AC**: all gates in `06-ci-cd.md` §2 run and block; total runtime under 8 minutes on a warm cache; a
  deliberate boundary violation, a non-EU region string, and a planted secret each fail the correct job.

### TNR-009 · Staging deployment · role `infra`
Terraform for Fly apps, R2 buckets, Cloudflare DNS; deploy workflow; secrets wiring.

- **Reading**: `02-architecture/09-infrastructure-and-devops.md`, ADR-0012, ADR-0009
- **Touches**: `infra/terraform/**`, `infra/fly/**`, `infra/docker/**`, `.github/workflows/main.yml`
- **AC**: merge to `main` deploys staging; migrations run as a separate job before rollout; `/healthz` responds
  with the deployed SHA; every region in config is EU.
- **Blocked by**: TNR-005, TNR-008

### TNR-010 · Seed data · role `api`
Deterministic seed as specified in the dev-setup doc, using real Argeș-county geography.

- **Reading**: `04-engineering/02-local-dev-setup.md` §5
- **Touches**: `packages/db/seed/**`
- **AC**: `pnpm db:seed` is deterministic across runs; two orgs exist so isolation is locally testable; all five
  seed users log in; every fixture coordinate passes the inside-Romania assertion.

---

# M1 — Identity and tenancy

### TNR-011 · Registration · role `api` — `FR-001`, `FR-002`, `FR-010`
- **Reading**: `02-architecture/06-auth-and-tenancy.md`, ADR-0008
- **Touches**: `apps/api/src/modules/auth/**`, `apps/api/src/modules/orgs/**`
- **AC**: user + org + owner membership created atomically; Argon2id at OWASP parameters; passwords under policy
  rejected; audit events written; no disclosure of whether an email exists.

### TNR-012 · Login, tokens, refresh rotation · role `api` — `FR-003`–`FR-006`, `FR-008`
- **Touches**: `apps/api/src/modules/auth/**`
- **AC**: 15-minute EdDSA access token with `kid`; 90-day opaque rotating refresh; **reuse revokes the whole
  family** and writes an audit event; per-IP and per-account backoff; no hard lockout.

### TNR-013 · Password reset · role `api` — `FR-007`
- **AC**: single-use token ≤ 60 min; always returns `202`; email lands in Mailpit locally.

### TNR-014 · Sessions list and revoke · role `api` — `FR-019`
- **AC**: sessions listed with device label and last-used; revoking one invalidates it within one access-token
  lifetime; a user sees only their own sessions.

### TNR-015 · Memberships and org switching · role `api` — `FR-009`, `FR-015`, `FR-126`
- **AC**: multi-org users switch without re-authenticating; the last owner cannot be removed or demoted; a user can
  leave an org unless they are its last owner.

### TNR-016 · Invitations · role `api` — `FR-011`–`FR-014`
- **AC**: single-use, ≤ 14 days, revocable; acceptance grants exactly the invited role; re-invite is idempotent;
  an invitation cannot grant more than the inviter's authority at acceptance time.

### TNR-017 · Permission model and guards · role `api` — `FR-017`, `FR-018`
- **Reading**: `02-architecture/06-auth-and-tenancy.md` §3
- **AC**: the full matrix is implemented; `<module>.permissions.ts` exists per module; **the service layer
  re-checks contextual rules**, not only the guard; denials return a problem document and are audit-logged.

### TNR-018 · Funder role and campaign grants · role `api` — `FR-016`, `FR-031`
- **AC**: a funder sees only granted campaigns; precise geometry fields are **omitted, not nulled**; grants are
  time-boxed and re-checked in the database per request, not trusted from the token.

### TNR-019 · Audit foundation · role `api` — `FR-100`–`FR-103`, `FR-106`
- **Reading**: `02-architecture/08-audit-and-donor-reporting.md` §2, ADR-0014
- **Touches**: `apps/api/src/modules/audit/**`, `apps/api/src/common/audit.interceptor.ts`
- **AC**: hash chain appends with the org row lock; event and change share one transaction; forcing an audit
  failure rolls back the change; `actor_type` includes `device` in the hash input from the first event; no update
  or delete path exists at any layer.

### TNR-020 · Chain verification endpoint · role `api` — `FR-105`
- **AC**: verifies a range and reports the exact `first_broken_seq`; a tampered row is detected; a nightly job
  verifies the previous day and alerts.

### TNR-021 · Adversarial tenancy suite · role `qa` — `FR-030`, `FR-032`, `NFR-030`
- **Reading**: `04-engineering/04-testing-strategy.md` §4.1, ADR-0016
- **Touches**: `apps/api/test/tenancy/**`
- **AC**: generated from the OpenAPI route list; every route and verb attempted cross-org; **a route without
  coverage fails CI**; cross-org reads return `404`, permission failures `403`.

### TNR-022 · Auth UI · role `web` — `US-A1`, `US-A3`
- **AC**: register, login, reset, accept-invitation flows; session persists across restart; **field mode boots
  fully usable with no network given a valid local session**.

### TNR-023 · Org and member admin UI · role `web` — `US-A2`
- **AC**: invite, list, change role, revoke; the UI hides actions the user lacks permission for, while the server
  enforces independently.

### TNR-024 · Rate limiting · role `api` — `FR-008`, `NFR-035`
- **AC**: buckets exactly as tabulated in `03-api-design.md` §12; `429` carries `Retry-After` and rate-limit
  headers; sync and presign limits are deliberately generous.

### TNR-025 · OpenAPI contract for M1 · role `shared`
- **AC**: every M1 endpoint is in `contracts/openapi.yaml`; generated types compile; the drift check passes.

---

# M2 — Field capture loop

### TNR-026 · Dexie stores and schema versioning · role `web` — `FR-025`, `NFR-012`
- **Reading**: `02-architecture/05-offline-first-and-sync.md` §2
- **AC**: stores for records, outbox, media queue, tiles, session; a migration with 500 pending entries loses
  nothing; quota exhaustion degrades gracefully.

### TNR-027 · Outbox implementation · role `web` — `FR-025`–`FR-027`, `NFR-013`
- **AC**: enqueue and local apply in one transaction (a forced abort leaves neither); `op_id` generated once;
  per-entity ordering preserved; retry classification and backoff exactly as specified; rejected entries leave the
  queue into a visible error list.

### TNR-028 · Sync endpoint · role `api` — `FR-034`, `FR-035`, `NFR-002`
- **Reading**: `02-architecture/05-offline-first-and-sync.md` §4
- **AC**: ≤ 50 mutations, 1 MB; **per-mutation transactions**, partial success; batch-level idempotency replay;
  clock skew computed and stored; derivations enqueued only after commit; p95 ≤ 500 ms for 20 mutations.

### TNR-029 · Sync client · role `web`
- **AC**: drains on `online`, foreground and manual trigger; handles all documented statuses; `401` mid-drain
  refreshes and resumes without loss.

### TNR-030 · Sighting model and endpoints · role `api` — `FR-020`, `FR-021`, `FR-036`
- **AC**: immutable after sync except moderation fields; `occurred_at` bound enforced; `notched_count_observed ≤
  animal_count_estimate`; GIST index used by the proximity query (verified with `EXPLAIN`).

### TNR-031 · Sighting capture UI · role `web` — `US-B1`, `NFR-001`, `NFR-061`
- **AC**: ≤ 4 taps and ≤ 15 s on a throttled mid-range profile; GPS pre-filled with accuracy shown and an
  adjustable pin; works fully offline; appears immediately as pending.

### TNR-032 · On-device image processing · role `web` — `FR-023`
- **AC**: ≤ 1600 px / ≤ 500 KB; EXIF capture time and GPS extracted **before** re-encoding; SHA-256 computed on
  device; runs off the main thread (no UI freeze on five images).

### TNR-033 · Media presign, finalise, link · role `api` — `FR-060`–`FR-062`, `FR-066`
- **AC**: bytes never transit the API; server-computed hash compared to the declared hash; mismatch quarantines and
  alerts; magic-byte validation; MIME allowlist enforced.

### TNR-034 · Media derivatives job · role `api` — `FR-063`, `FR-064`
- **AC**: thumb and web variants; **EXIF stripped from derivatives, preserved on originals**; failure leaves the
  original usable.

### TNR-035 · Media upload client queue · role `web` — `FR-022`, `NFR-014`
- **AC**: independent of the outbox — a failed photo never blocks a sighting; resumes after restart; Wi-Fi-only
  default for originals with a per-item override.

### TNR-036 · Media garbage collection · role `api` — `FR-067`
- **AC**: unlinked media reaped after 48 h and logged; the job refuses to run above a sanity threshold.

### TNR-037 · Pack model and clustering job · role `api` — `FR-040`–`FR-042`, `FR-046`
- **Reading**: `02-architecture/04-geospatial-and-routing.md` §3
- **AC**: scoring exactly as specified; idempotent re-run; serialised per org by advisory lock; never on the
  request path; every decision audited with `actor_type='system'`.

### TNR-038 · Pack curation endpoints · role `api` — `FR-043`, `FR-044`
- **AC**: merge, split, close (reason required), confirm, rename; every operation audits the affected sighting ids;
  reversible within 30 days; merged packs retained forever.

### TNR-039 · Map with MapLibre + PMTiles · role `web` — `FR-038`, `NFR-008`
- **Reading**: `02-architecture/04-geospatial-and-routing.md` §5, ADR-0007
- **AC**: pack and sighting layers; the client handles both feature and cluster representations; **OSM attribution
  present**; viewport queries bounded.

### TNR-040 · Offline tile caching · role `web` — `FR-029`, `NFR-005`
- **AC**: region selection, zooms 8–14, 150 MB budget with an 80% warning, whole-region LRU eviction; uncached
  areas render as an explicit hatched state, never blank.

### TNR-041 · Pack console UI · role `web` — `US-C1`, `US-C2`
- **AC**: proposal queue, merge/split/close with confirmation, notched ratio visible, every automatic decision
  shown with its confidence.

### TNR-042 · Sync status UI · role `web` — `FR-027`, `NFR-064`
- **AC**: the state table in `05-offline-first-and-sync.md` §9 implemented exactly; no indefinite spinner; never
  says "saved" for a queued item; the database cannot be cleared while the outbox is non-empty.

### TNR-043 · Romanian localisation · role `web` — `NFR-021`, `NFR-022`
- **AC**: full `ro` catalogue; Romanian default for Romanian locales; no concatenated fragments; CI fails on a
  missing key.

### TNR-044 · Offline durability test suite · role `qa` — `NFR-012`, `NFR-013`
- **Reading**: `04-engineering/04-testing-strategy.md` §4.2
- **AC**: every scenario in that table, **including the 7-day soak**, automated and green.

### TNR-045 · Pull endpoint for assigned scope · role `api`
- **AC**: cursor-based; `scope=assigned` returns a bounded set; console does not use it.

---

# M3 — Operations loop

### TNR-056 · Vehicle model and CRUD · role `api` — `FR-082`
### TNR-057 · Mission model and lifecycle · role `api` — `FR-070`, `FR-072`, `FR-083`
- **AC**: transitions enforced server-side; illegal transition returns `409`.
### TNR-058 · Mission stops · role `api` — `FR-078`, `FR-079`
- **AC**: sequence unique per mission; outcomes with skip reasons; field-observed timestamps and device location
  preserved.
### TNR-059 · OSRM + VROOM container · role `infra` — ADR-0011
- **AC**: graph baked at build time; matrix cached in Redis by rounded coordinates, 30-day TTL.
### TNR-060 · Optimisation job · role `api` — `FR-073`, `FR-074`, `NFR-006`
- **AC**: capacity and time window honoured; engine and version recorded; ≤ 10 s p95 for 25 stops.
### TNR-061 · Straight-line fallback · role `api` — `FR-075`
- **AC**: `optimisation_mode='fallback_straight_line'`; **labelled in every UI surface**.
### TNR-062 · Manual reorder · role `api` — `FR-076`
- **AC**: manual order persists; re-optimisation requires explicit confirmation.
### TNR-063 · Mission cache bundle · role `api` — `FR-077`
- **AC**: one call returns stops, pack details, notes and the tile-corridor descriptor.
### TNR-064 · Mission builder UI · role `web` — `US-D1`, `FR-071`
- **AC**: select packs on map or list; capacity fit shown; duplicate-targeting warns without blocking.
### TNR-065 · Mission execution UI (offline) · role `web` — `US-D3`
- **AC**: full stop-by-stop execution in aeroplane mode; outcomes queue and sync.
### TNR-066 · Planned vs actual · role `api` + `web` — `FR-080`, `FR-081`
- **AC**: unknown actuals display as unknown, **never zero**.
### TNR-067 · Mission e2e test · role `qa`
- **AC**: 15-stop mission planned, optimised, executed offline, synced, reconciled.

---

# M4 — Proof loop

### TNR-076 · Animal model and endpoints · role `api` — `FR-050`–`FR-053`, `FR-057`, `FR-058`
- **AC**: microchip 15 digits, unique per org, non-`642` accepted and flagged; sterilisation status derived only;
  `household_ref` carries no personal data.
### TNR-077 · Animal–pack temporal membership · role `api` — `FR-047`, `FR-053`
### TNR-078 · Intervention model · role `api` — `FR-090`, `FR-091`, `FR-095`–`FR-098`, ADR-0018
- **AC**: append-only; euthanasia requires vet and justification and is never presented as population control;
  sterilisation sets `confirmed_sterilised`; `intervention_effective` view used by all reporting.
### TNR-079 · Intervention correction · role `api` — `FR-093`
- **AC**: `/correct` creates a superseding record; both retained; no `PATCH` on core fields exists.
### TNR-080 · Intervention capture UI (offline) · role `web` — `US-E1`
- **AC**: ≤ 60 s per animal; offline; local chip-format validation.
### TNR-081 · Evidence media on interventions · role `api` + `web` — `FR-094`
- **AC**: before/after roles; hash, capture time and uploader shown in the evidence view.
### TNR-082 · Metric projections · role `api` — `FR-110`–`FR-112`
- **AC**: the full metric catalogue; 5-minute incremental refresh with a nightly full recompute; **rebuildable from
  source and tested**; freshness exposed.
### TNR-083 · Campaign and grant models · role `api`
### TNR-084 · Campaign dashboard · role `web` — `US-F1`, `NFR-007`
- **AC**: ≤ 2 s p95 at 50k interventions; every aggregate drillable; freshness timestamp visible.
### TNR-085 · Donor report generation · role `api` — `FR-113`–`FR-116`, `NFR-009`
- **AC**: `ro`/`en`/`de`; **byte-identical on regeneration from the same snapshot**; snapshot time and audit head
  hash printed; methodology section present.
### TNR-086 · Evidence pack · role `api` — `FR-117`, `FR-118`
- **AC**: streamed archive; manifest hashes verify; **the `VERIFY.md` procedure runs in CI**; the pack's own hash
  is audited.
### TNR-087 · Coverage metric with stated denominator · role `api` — `FR-119`
- **AC**: every coverage display names its denominator source and labels itself an estimate. **Blocked by
  OQ-DM-3.**
### TNR-088 · RECS CSV export · role `api` — `FR-056`, `FR-104`
- **AC**: column order verified against the current RECS form; versioned `recs_csv_v1`; audit-logged with row
  count.
### TNR-089 · Chip lookup integration · role `api` — `FR-054`, `FR-055`
- **AC**: async, cached 30 days, rate-limited, sequential; failure yields `unknown` and never blocks; labelled
  unofficial; disable-able by configuration.
### TNR-090 · Evidence integrity test suite · role `qa`
- **AC**: every scenario in `04-testing-strategy.md` §4.3 automated.

---

# M5 — Production readiness

### TNR-101 · GDPR export · role `api` — `FR-120`, `FR-122`
### TNR-102 · GDPR erasure with pseudonymisation · role `api` — `FR-121`
- **AC**: personal identifiers removed, operational records retained anonymised, legal basis recorded, chain
  intact (the chain never held personal data by design).
### TNR-103 · Retention sweep · role `api` — `FR-123`
- **AC**: per-class configurable periods; the job logs every action.
### TNR-104 · Backups and restore drill · role `infra` — `NFR-023`, `NFR-024`
- **AC**: PITR verified by an actual restore into a scratch database; measured RTO recorded; bucket versioning
  confirmed.
### TNR-105 · Runbooks · role `docs`
- **AC**: all ten initial scenarios written for a tired operator: symptom, causes by probability, commands,
  remediation.
### TNR-106 · Observability · role `infra` — `NFR-040`–`NFR-044`
- **AC**: structured logs with **tested structural redaction**; the full metric set; sampled tracing; error
  tracking with EU residency and no PII.
### TNR-107 · Alerting · role `infra` — `NFR-043`
- **AC**: exactly the six pageable alerts; every alert links to a runbook section.
### TNR-108 · Load testing · role `qa`
- **AC**: `NFR-002`, `NFR-006`, `NFR-007`, `NFR-008` all verified under k6 against a seeded large dataset.
### TNR-109 · Accessibility pass · role `web` — `NFR-060`–`NFR-065`
- **AC**: axe clean on console; field touch targets ≥ 48 px; sunlight-contrast check; no colour-only information.

### TNR-117 · Terraform for production · role `infra`
### TNR-118 · Licence decision · role `docs`
### TNR-119 · DPA, privacy policy, Article 30 record · role `docs` — `FR-125`
- **AC**: DPA signable; ROPA in `docs/compliance/ropa.md`; sub-processor list published; DPIA completed.
### TNR-120 · Security review · role `qa`
- **AC**: the threat model in `11-security-and-gdpr.md` walked end to end; findings triaged; **resolve OQ-SEC-1**
  (MFA for owner/admin).

---

# Cross-cutting and deferred

| ID | Item | Notes |
|---|---|---|
| `TNR-095` | Coverage choropleth | Blocked by OQ-DM-3 (dog-population data source) |
| `TNR-098` | Multi-vehicle optimisation | VROOM already supports it; parameter + UI |
| `TNR-099` | Service-time calibration | After the first real campaign |
| `TNR-110` | Ear-notch ML detection | Gated by ADR-0017 corpus thresholds |
| `TNR-115` | Public sighting intake | Needs a trust-level model first |
| `TNR-116` | Bulk CSV import | First onboarding |
| `TNR-121` | OSRM graph refresh procedure | Quarterly, documented |
| `TNR-122` | Cost monitoring | Alert at 150% of the 7-day mean |

## Open questions blocking work

| ID | Question | Blocks |
|---|---|---|
| **OQ-INFRA-1** | Managed Postgres provider | TNR-002 |
| **OQ-GEO-1** | Romanian locality boundaries: source and licence | TNR-087, TNR-095 |
| **OQ-DM-3** | Dog-population estimates per locality | TNR-087, TNR-095 |
| **OQ-SEC-1** | MFA mandatory for owner/admin? | TNR-120 |
| **OQ-MEDIA-1** | HEIC: transcode or reject? | Before the first iOS-heavy customer |
| **OQ-INFRA-2** | Chromium in worker, or a separate PDF service? | TNR-085 sizing |

An agent hitting one of these **must not invent an answer**. Resolve it in an ADR or escalate (`docs/README.md`,
document conventions).
