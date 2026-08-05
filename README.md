# TNR-OS

**Geospatial command and fleet-logistics platform for Trap–Neuter–Return (TNR) campaigns in Romania.**

TNR-OS replaces the WhatsApp groups, corrupted spreadsheets and unreliable word-of-mouth that animal-welfare
NGOs currently use to run sterilisation campaigns. Field volunteers drop geolocated sightings from an
offline-capable phone app; shelter coordinators turn those sightings into optimised capture routes for their
vehicles and mobile clinics; and every surgery produces a tamper-evident, geolocated, timestamped audit trail
that unlocks funding from international institutional donors.

Phase 1 is **pure software**. Phase 2 adds IoT trap sensors that plug into the same API. The architecture is
designed today so that Phase 2 is an additive change, not a rewrite — see
[`docs/02-architecture/12-phase-2-iot-seams.md`](docs/02-architecture/12-phase-2-iot-seams.md).

---

## Status

| | |
|---|---|
| Phase | 1 — software MVP |
| Stage | Pre-implementation (architecture complete, no application code yet) |
| Target first customer | 1 Romanian NGO running mobile-clinic TNR campaigns |
| Primary region | EU (Frankfurt) — GDPR data residency |

## Documentation

Everything needed to build this system lives in [`docs/`](docs/README.md). Start there.

Fast paths:

- **New human contributor** → [`docs/README.md`](docs/README.md), then [`docs/02-architecture/01-system-overview.md`](docs/02-architecture/01-system-overview.md)
- **AI agent picking up a task** → [`AGENTS.md`](AGENTS.md), then [`docs/05-delivery/03-agent-playbook.md`](docs/05-delivery/03-agent-playbook.md)
- **Why is it built this way?** → [`docs/03-adr/`](docs/03-adr/)
- **What do I build next?** → [`docs/05-delivery/02-backlog.md`](docs/05-delivery/02-backlog.md)

## Normative contracts

Two files are the single source of truth for cross-cutting shape. Code must conform to them; docs describe them.

- [`contracts/openapi.yaml`](contracts/openapi.yaml) — HTTP API surface
- [`contracts/db/migrations/0001_init.sql`](contracts/db/migrations/0001_init.sql) — database schema

If an implementation disagrees with a contract, the contract wins until an ADR changes it.

## Architecture at a glance

```
Field volunteer (PWA, offline-first)   Coordinator (web dashboard)
              │                                   │
              └───────────────┬───────────────────┘
                              │ HTTPS / REST (v1)
                     ┌────────▼────────┐
                     │   API (NestJS)  │──── presigned PUT ──▶ Object storage (R2)
                     └───┬─────────┬───┘
                         │         │ BullMQ jobs
            ┌────────────▼──┐  ┌───▼──────────┐   ┌──────────────┐
            │ PostgreSQL 16 │  │   Workers    │──▶│ OSRM + VROOM │
            │   + PostGIS   │  │ (routing,    │   │  (routing)   │
            └───────────────┘  │  media, PDF) │   └──────────────┘
                               └──────────────┘
```

Phase 2 adds an MQTT ingest bridge that authenticates trap devices and writes the same `sighting`/`capture`
events through the same service layer.

## Tech stack

TypeScript end to end. React 19 + Vite PWA + MapLibre on the client; NestJS (Fastify) + Drizzle ORM on the
server; PostgreSQL 16 + PostGIS as system of record; Redis + BullMQ for async work; S3-compatible object
storage for media; containers on Fly.io Frankfurt. Rationale for each choice is in [`docs/03-adr/`](docs/03-adr/).

## Repository layout

The application code does not exist yet. The intended structure is specified in
[`docs/04-engineering/01-repo-structure.md`](docs/04-engineering/01-repo-structure.md) and must be followed
when scaffolding begins (backlog item `TNR-001`).

```
.
├── AGENTS.md          # operating rules for AI agents and humans
├── contracts/         # normative API + DB contracts
├── docs/              # architecture, product, engineering, delivery docs
├── apps/              # (to be created) api, web, worker
└── packages/          # (to be created) shared types, db, config, ui
```

## Licence

Not yet chosen. See `TNR-118` in the backlog.
