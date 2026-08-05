# Roadmap

Milestones are defined by **capability**, not by date. A solo founder with agent assistance cannot forecast dates
honestly, but can say exactly what must be true to move on.

Each milestone has an exit criterion. Do not start the next one until it is met — half-finished vertical slices
across three milestones is the failure mode this structure prevents.

---

## M0 — Foundation

**Goal:** an empty but correct system that deploys.

Scope: monorepo scaffold, Docker Compose, Postgres+PostGIS, initial migration, NestJS skeleton with global
guards/interceptors/filters, React app shell with field and console routes, CI pipeline, staging deploy.

**Exit:** a health endpoint responds in staging, deployed by CI from `main`, with migrations applied and the
adversarial-tenancy harness running (even with one route).

Items: `TNR-001`–`TNR-010`

Why first: the cross-cutting mechanisms (org scoping, audit interception, idempotency, problem-json) must exist
before the first real endpoint, or every subsequent endpoint retrofits them inconsistently.

## M1 — Identity and tenancy

**Goal:** real users in real orgs with real isolation.

Scope: registration, login, refresh rotation, sessions, invitations, memberships, roles and permissions, org
switching, the full permission matrix, audit events for identity, and the generated adversarial tenancy suite.

**Exit:** two orgs coexist; a volunteer in org A cannot reach anything in org B on any route; the tenancy suite
covers every existing route and fails when a route is added without coverage.

Items: `TNR-011`–`TNR-025`

## M2 — Field capture loop (Loop 1)

**Goal:** a volunteer captures sightings offline and a coordinator sees packs.

Scope: PWA shell and service worker, Dexie stores, outbox, `/v1/sync` with per-mutation results, sighting capture
UI, media pipeline (presign → upload → finalise → derivatives), pack clustering job, pack curation (merge, split,
close, confirm), map with MapLibre + PMTiles, offline tile caching, Romanian localisation.

**Exit:** on a real phone, in aeroplane mode, capture 5 sightings with photos, kill the app, reopen, reconnect —
everything arrives exactly once, packs are proposed, and a coordinator sees them on a map.

Items: `TNR-026`–`TNR-055`

This is the milestone that proves the product. If offline capture is not trustworthy, nothing after it matters.

## M3 — Operations loop (Loop 2)

**Goal:** a coordinator plans a mission and a team executes it offline.

Scope: vehicles, mission CRUD and lifecycle, stop management, OSRM+VROOM optimisation with capacity and time
windows, straight-line fallback, mission cache bundle for offline execution, stop outcomes offline, planned versus
actual distance.

**Exit:** build a 15-stop mission, optimise it, execute it from a phone in aeroplane mode, sync outcomes, and see
planned versus actual on the console.

Items: `TNR-056`–`TNR-075`

## M4 — Proof loop (Loop 3)

**Goal:** interventions become fundable evidence.

Scope: animals with microchip validation, intervention recording (offline, append-only, supersede corrections),
before/after evidence media, hash-chained audit end to end, chain verification endpoint, metric projections,
campaign dashboard, donor report PDF in three locales, evidence packs with `VERIFY.md`, RECS CSV export.

**Exit:** generate a donor report for a campaign; hand the evidence pack to someone with no access to our systems;
they verify every hash using only the instructions in the pack.

Items: `TNR-076`–`TNR-100`

## M5 — Production readiness

**Goal:** safe to put a real NGO's real data in.

Scope: GDPR tooling (export, erasure, retention sweep), backups and a rehearsed restore, runbooks, alerting,
observability dashboards, rate limiting, load testing against the NFR budgets, accessibility pass, DPA and privacy
policy, security review.

**Exit:** restore drill completed with a measured RTO inside `NFR-023`; all NFR budgets met under load; a DPA is
signable.

Items: `TNR-101`–`TNR-125`

## Post-M5 — First customer

Not a development milestone. Onboarding, data import from whatever spreadsheets they have, training, and the first
real campaign. Expect the backlog to be rewritten by what is learned here; that is the point of shipping.

Watch for: what they try to do that the product refuses; what they keep doing in Excel anyway; which report
question the funder asks that we cannot answer.

---

## Phase 1.5 candidates

Not scheduled. Ordered by expected value, to be re-ranked with real customer input:

| Item | Trigger |
|---|---|
| Ear-notch ML detection (`TNR-110`) | ≥ 5,000 labelled ear crops (ADR-0017) |
| Multi-vehicle joint optimisation (`TNR-098`) | A customer runs ≥ 3 vehicles on the same day |
| Coverage choropleth (`TNR-095`) | Locality dog-population data resolved (OQ-DM-3) |
| Bulk CSV import (`TNR-116`) | First onboarding with existing spreadsheet history |
| Public sighting intake (`TNR-115`) | Only with a trust-level model; poisons the data moat otherwise |
| Passkeys for the console | Customer request |
| Service-time calibration from real stops (`TNR-099`) | After the first full campaign |

## Phase 2 trigger

Development of IoT trap sensors starts only when **all** hold:

- ≥ 3 paying NGO organisations, ≥ 12 months combined retention
- ≥ 5,000 interventions recorded through the platform
- ≥ 20 vehicles coordinated in a single season
- Customers independently asking for cage-monitoring automation

Until then, Phase 1 owes Phase 2 only the seams in
[`../02-architecture/12-phase-2-iot-seams.md`](../02-architecture/12-phase-2-iot-seams.md) §5 — which are already
in M0's initial migration, costing nothing extra.

## Sequencing rationale

The order is not arbitrary:

1. **Tenancy before features.** Retrofitting isolation is a rewrite, and the failure it prevents is the worst one.
2. **Capture before planning.** Planning needs data; data comes from capture. Building mission planning against
   seed data would optimise for a fiction.
3. **Operations before reporting.** Reports need real interventions from real missions.
4. **Evidence last among the loops, but before the customer.** It is the payer's surface, and it depends on
   everything upstream being real.
5. **Production readiness before real data**, without exception. Putting a real NGO's household-identifying
   location data into a system without backups, retention and a DPA would be indefensible.

## Explicitly not on the roadmap

TRACES/CHED export compliance, municipal/B2G surfaces, native mobile apps, in-product billing, real-time vehicle
tracking, adoption marketplace, donation collection. Reasons in
[`../01-product/01-scope-and-personas.md`](../01-product/01-scope-and-personas.md) §3.
