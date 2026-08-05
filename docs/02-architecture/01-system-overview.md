# System overview

## 1. Design principles

These are the tie-breakers. When two designs are otherwise equal, the one that better satisfies a
higher-numbered-priority principle wins.

1. **Offline is the normal case, not the exception.** The field client is the system of record until it syncs.
   Every write path is designed to be replayed.
2. **Evidence is immutable.** Interventions and media are append-only, hash-chained and independently
   verifiable. Convenience never overrides this.
3. **One tenant boundary, enforced in one place.** Org scoping lives in the service layer, not in controllers or
   the UI, and is verified by an adversarial test suite.
4. **Boring, portable infrastructure.** A solo founder cannot operate a distributed system. One Postgres, one
   API, one worker pool, containers that run anywhere.
5. **Derivations are asynchronous.** Clustering, routing, thumbnails and reports never sit on an interactive
   request path.
6. **Seams for Phase 2, not scaffolding.** Device identity and event ingest are cheap to design now and
   expensive to retrofit — but we build only the boundary, not the feature.

## 2. Context view (C4 level 1)

```
                  ┌────────────────────────────────────────┐
   Mihai ────────▶│                                        │
  (volunteer,     │              TNR-OS                    │──▶ Object storage (media, EU)
   offline PWA)   │  sightings · packs · animals ·         │
   Ana ──────────▶│  missions · interventions · audit ·    │──▶ Routing engine (OSRM + VROOM, self-hosted)
  (coordinator)   │  reports                               │
   Elena ────────▶│                                        │──▶ Microchip lookup (RomPetID / Europetnet) [best effort]
  (veterinarian)  │                                        │
   Klaus ────────▶│                                        │──▶ Transactional email (invites, resets, report links)
  (funder, PDFs)  └────────────────────────────────────────┘
                                    │
                          [Phase 2] │ MQTT ingest ◀── trap devices (ESP32 + NB-IoT)
                                    ▼
```

External systems and their failure posture:

| System | Used for | If unavailable |
|---|---|---|
| Object storage (Cloudflare R2, EU) | Media originals + derivatives, report artefacts | Sightings still save; media stays queued on device (`NFR-016`) |
| Routing engine (OSRM + VROOM) | Distance matrix + stop ordering | Fall back to labelled nearest-neighbour ordering (`FR-075`) |
| Microchip lookup portals | Enrichment only | Result is "unknown"; never blocks a write (`FR-054`) |
| Email provider | Invitations, resets, report notifications | Queue and retry; no core flow blocked |
| Tile host (PMTiles on R2) | Basemap | Cached tiles or a plain grid; pin capture still works |
| **RECS / CMV** | **Nothing.** No API exists. We never claim to write to it | n/a |

## 3. Container view (C4 level 2)

```
┌──────────────────────────┐        ┌──────────────────────────┐
│  web (React 19 + Vite)   │        │  web console (same app,  │
│  FIELD MODE — PWA        │        │  CONSOLE MODE)           │
│  Dexie outbox, SW cache  │        │  MapLibre, dense tables  │
└───────────┬──────────────┘        └───────────┬──────────────┘
            │  HTTPS /v1  (JWT access token, Idempotency-Key)
            └───────────────┬────────────────────┘
                            ▼
        ┌───────────────────────────────────────────────┐
        │ api  —  NestJS on Fastify (stateless)         │
        │ modules: auth · orgs · sightings · packs ·    │
        │ animals · missions · interventions · media ·  │
        │ reports · audit · sync · admin                │
        │ cross-cutting: OrgScope guard, idempotency,   │
        │ problem-json filter, audit interceptor         │
        └────┬───────────────┬──────────────┬───────────┘
             │ SQL           │ enqueue      │ presign
             ▼               ▼              ▼
    ┌────────────────┐  ┌──────────┐   ┌──────────────┐
    │ PostgreSQL 16  │  │  Redis   │   │ Object store │
    │ + PostGIS 3.4  │  │ BullMQ   │   │  (R2, EU)    │
    │ system of      │  └────┬─────┘   └──────────────┘
    │ record         │       │
    └────────────────┘       ▼
             ▲    ┌────────────────────────────────────┐
             └────│ worker — same codebase, no HTTP     │
                  │ jobs: cluster-sighting ·            │
                  │ optimise-mission · process-media ·  │
                  │ generate-report · build-evidence ·  │
                  │ lookup-microchip · refresh-metrics ·│
                  │ retention-sweep                     │
                  └──────────────┬─────────────────────┘
                                 ▼
                     ┌──────────────────────┐
                     │ OSRM + VROOM (RO)    │
                     └──────────────────────┘
```

**Three deployable units**: `api`, `worker`, `web` (static). Plus stateful dependencies. That is the entire
production topology for Phase 1 — deliberately.

`api` and `worker` share one codebase and one domain layer. A job handler calls the same service a controller
calls. There is no duplicated business logic and no separate "job models".

## 4. Component view — inside `api`

Layered, with strictly one-directional dependencies:

```
HTTP layer      controllers, DTOs (Zod), guards, interceptors
                  │  may only call ▼
Domain layer    services: business rules, invariants, state machines, authorisation decisions
                  │  may only call ▼
Data layer      repositories (Drizzle), spatial queries, unit-of-work/transaction
                  │  may only call ▼
Infrastructure  Postgres, Redis, object storage, HTTP adapters for external systems
```

Rules enforced by lint boundaries (`TNR-005`):

- Controllers contain no business logic and no SQL. They validate, delegate, and map to a response DTO.
- Services never import HTTP types (`Request`, `Response`) and never construct SQL strings.
- Repositories never make authorisation decisions.
- Anything talking to a third party sits behind an interface in the domain layer with a fake for tests.

Every module follows the same file shape so agents can navigate any module they have not read:

```
apps/api/src/modules/<module>/
  <module>.controller.ts     HTTP surface
  <module>.service.ts        business rules
  <module>.repository.ts     data access
  <module>.schema.ts         Zod request/response schemas
  <module>.events.ts         domain events emitted
  <module>.permissions.ts    required permissions per operation
  __tests__/
```

## 5. Key request flows

### 5.1 Offline sighting → pack proposal

```
1. Mihai submits a sighting with no connectivity.
2. Client writes to Dexie: record + UUIDv7 id + occurred_at + outbox entry with an idempotency key.
3. UI shows the sighting immediately as "pending". Photos are queued separately.
4. Connectivity returns. Client POSTs /v1/sync with a batch of ≤ 50 mutations.
5. api validates, resolves org from the session, applies each mutation in its own transaction:
   insert sighting + audit event, both committed together.
6. api returns per-mutation results (applied | duplicate | rejected + reason). Duplicate is a success.
7. api enqueues cluster-sighting. Response is returned without waiting for it.
8. worker finds packs within 300 m / 90 days. Attaches, or proposes a new pack with status `proposed`.
9. Media upload runs on its own schedule: presign → PUT to storage → finalise → process-media job.
10. Ana sees the sighting and the pack proposal on the console within 5 minutes.
```

Note what is *not* in the interactive path: clustering, thumbnails, metric refresh. Sync stays under 500 ms
(`NFR-002`) because it only writes and enqueues.

### 5.2 Mission planning

```
1. Ana selects packs, a vehicle and a date; POST /v1/missions creates it as `draft`.
2. POST /v1/missions/{id}/optimise enqueues optimise-mission and returns 202 + job id.
3. worker builds the stop set, calls OSRM for a duration matrix, hands VROOM the capacity and time-window
   constraints, receives an ordered solution.
4. worker writes stop order, ETAs, planned distance/duration, engine name and version; emits mission.optimised.
5. Console polls the job (or receives it on next refresh) and renders the ordered plan.
6. If VROOM/OSRM is down, the job fails cleanly and the API offers nearest-neighbour ordering flagged
   `optimisation: "fallback_straight_line"` so the UI can label it honestly.
```

### 5.3 Intervention → evidence pack

```
1. Elena records an intervention (offline-capable) with before/after photos.
2. On sync the intervention is inserted append-only, with an audit event chained to the org's previous event.
3. Media finalisation computes SHA-256 server-side and compares it with the client's declared hash;
   a mismatch quarantines the object and alerts.
4. Ana requests an evidence pack for a campaign and period → build-evidence job.
5. worker streams a ZIP: report PDF, interventions CSV, media manifest (path, hash, capture time, uploader),
   audit-chain excerpt, VERIFY.md.
6. The pack's own hash is written into the audit log; the download link is signed and short-lived.
```

## 6. Frontend architecture

One React application, two modes, one codebase:

| | Field mode | Console mode |
|---|---|---|
| Route prefix | `/f/*` | `/c/*` |
| Optimised for | offline, gloves, speed, battery | map density, bulk operations, reporting |
| Bundle budget | ≤ 250 KB gz (`NFR-004`) | ≤ 600 KB gz, map lazy-loaded |
| Data source | Dexie first, network second | network first, TanStack Query cache |
| Map | minimal, cached tiles | full MapLibre with clustering |

Field mode is a separate lazy chunk and must not import console-only libraries (charts, PDF preview, data
grid). This is enforced by a bundle-composition check, not by good intentions (`TNR-006`).

State layering:

- **Server state** → TanStack Query. Never mirrored into a global store.
- **Local durable state** → Dexie (records, outbox, media queue, cached missions).
- **Ephemeral UI state** → component state; Zustand only for genuinely cross-cutting UI (active org, connectivity, map viewport).

## 7. Data flow and ownership

| Data | Owner | Written by | Mutability |
|---|---|---|---|
| Sightings | field client | client (offline) → sync | immutable after sync except moderation fields |
| Packs | server | worker (proposal) + coordinator (curation) | mutable, fully audited |
| Animals | server | vet/coordinator | mutable, audited; sterilisation status derived |
| Interventions | vet client | vet (offline-capable) → sync | **append-only**; corrections supersede |
| Missions & stops | server | coordinator; stop outcomes from field | mutable until `completed` |
| Media | client → storage | client direct PUT | immutable; new version supersedes |
| Audit events | server | every mutation, same transaction | **never** mutable |
| Metric projections | server | scheduled job | derived, rebuildable from source |

Anything in the "derived" category must be reconstructible from the source tables by a documented job. If a
projection cannot be rebuilt, it is not a projection, it is unversioned state — and that is a defect.

## 8. Failure modes and responses

| Failure | Blast radius | Response |
|---|---|---|
| API down | No sync, no console | Field capture continues offline; outbox drains on recovery |
| Postgres down | All writes | API returns 503 with `Retry-After`; clients keep queueing; no data loss |
| Redis down | Async jobs stall | Interactive paths unaffected; jobs resume; queue depth alert |
| Object storage down | Media upload/serving | Sighting and intervention records unaffected; media retries |
| Routing engine down | Optimisation | Labelled fallback ordering (`FR-075`) |
| Worker crash-looping | Derivations stale | Dashboard shows staleness honestly (`FR-112`); alert on projection age |
| Client cache corruption | One device | Reset-and-resync path that preserves the outbox first; never blind-wipes pending data |
| Clock skew on device | Ordering | Server never trusts client clocks for ordering; skew recorded (`NFR-018`) |

## 9. Scale envelope

Phase 1 must handle, on one Postgres instance without partitioning: 50 orgs, 2,000 users, 500k sightings, 200k
interventions, 5M media objects (`NFR-051`). At roughly 10× that, the expected first moves are (a) read replica
for reporting, (b) partition `sighting` and `audit_event` by month, (c) separate the media-processing worker
pool. None of these require a redesign, which is the point of keeping the topology boring.

## 10. Explicitly rejected architectures

| Rejected | Why |
|---|---|
| Microservices per domain | A solo founder cannot operate distributed transactions or six deploy pipelines. Modular monolith with hard internal boundaries gets the same discipline at a fraction of the cost |
| Event sourcing everywhere | Only evidence needs immutability; event-sourcing the whole domain would triple complexity for no product gain. Audit chain gives us the guarantee where it matters |
| BaaS (Supabase/Firebase) as the backend | Offline conflict rules, hash-chained audit, capacity-constrained routing and evidence packs are custom domain logic. Lock-in on the audit path is unacceptable, and EU-residency control matters (ADR-0012) |
| Native mobile apps | Cost and release friction for a solo founder; PWA meets the field requirements (ADR-0006) |
| GraphQL | One client, cursor-paginated lists, offline batching. REST + generated types is simpler to keep contractually stable across offline client versions (ADR-0004) |
| Realtime sync engine (CRDT) | Sightings are append-only observations, not collaboratively edited documents. An outbox with idempotency keys solves the actual problem (ADR-0006) |
