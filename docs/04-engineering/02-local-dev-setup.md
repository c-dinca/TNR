# Local development setup

Goal: **one command brings up a complete, seeded environment** (`NFR-046`).

> This describes the environment that `TNR-001`–`TNR-004` create. Until those are done, only the documentation
> exists. If a command here fails because a file is missing, the backlog item that creates it has not run yet —
> that is expected, not a bug to chase.

---

## 1. Prerequisites

| Tool | Version | Check |
|---|---|---|
| Node | 22 LTS | `node -v` |
| pnpm | 9.x | `pnpm -v` |
| Docker + Compose v2 | current | `docker compose version` |
| Git | 2.40+ | `git --version` |

Use a Node version manager (`fnm`, `nvm`, `mise`); the version is pinned in `.nvmrc` and `package.json#engines`.
Enable pnpm with `corepack enable`.

Recommended: at least 8 GB RAM available to Docker. The Postgres, Redis, MinIO and OSRM containers together want
roughly 3 GB, and OSRM is the greedy one.

## 2. Bootstrap

```bash
git clone <repo> && cd tnr-os
cp .env.example .env
pnpm install
pnpm infra:up          # Postgres+PostGIS, Redis, MinIO, Mailpit, OSRM+VROOM
pnpm db:migrate
pnpm db:seed
pnpm dev
```

| Service | URL | Notes |
|---|---|---|
| Web | http://localhost:5173 | Vite dev server |
| API | http://localhost:3000 | `/docs` serves Swagger UI |
| Postgres | localhost:5432 | `tnr` / `tnr` / `tnr_dev` |
| Redis | localhost:6379 | |
| MinIO | http://localhost:9001 | S3-compatible; console `minioadmin`/`minioadmin` |
| Mailpit | http://localhost:8025 | Catches all outbound email |
| OSRM/VROOM | http://localhost:5000 / 3001 | Romania graph |

`pnpm dev` is long-running. Start it in the background and keep working; do not block on it.

## 3. Compose services

```yaml
postgres:  postgis/postgis:16-3.4     # NOT plain postgres — PostGIS is required
redis:     redis:7-alpine
minio:     minio/minio                # S3-compatible local object storage
mailpit:   axllent/mailpit            # SMTP sink with a web UI
osrm:      tnr/osrm-vroom:local       # built locally, see below
```

The OSRM image needs a one-time build with a Romania extract (~250 MB download, 10–20 minutes):

```bash
pnpm infra:build-osrm
```

Skip it if you are not working on routing. `OSRM_URL` unset makes optimisation fall back to straight-line ordering
(`FR-075`), which is precisely the degraded mode the product must support anyway.

## 4. Environment variables

`.env.example` is the canonical list and is validated by a Zod schema at boot (`NFR-032`). A missing or malformed
value crashes at startup, deliberately — never at first use, three hours later.

Never commit `.env`. Never put a real credential in `.env.example`; use an obvious placeholder.

## 5. Seed data

`pnpm db:seed` creates a realistic dataset in real Romanian geography:

| Entity | Contents |
|---|---|
| Orgs | 2 (`Asociația Test Pitești`, `Test NGO Slatina`) — the second exists so cross-org isolation is testable locally |
| Users | One per role, password `dev-password-123` |
| Localities | ~40 real localities in Argeș county with SIRUTA codes |
| Packs | 25 across those localities, mixed statuses |
| Sightings | ~400 over 6 months, clustered around packs |
| Animals | 120, some chipped, some notched |
| Interventions | ~200 including corrections and one superseded chain |
| Vehicles | 3 including a mobile clinic |
| Missions | 8 across all lifecycle states |
| Campaign | 1 active with a grant |
| Media | Placeholder images with valid EXIF |

Seed data is deterministic (fixed seed), so a bug reproduces identically for another agent. `pnpm db:reset` drops,
migrates and reseeds.

Local seed users:

| Email | Role |
|---|---|
| `owner@test.ro` | owner |
| `ana@test.ro` | coordinator |
| `elena@test.ro` | vet |
| `mihai@test.ro` | volunteer |
| `klaus@foundation.de` | funder |

## 6. Common tasks

```bash
pnpm dev --filter @tnr/api          # one app only
pnpm test                            # unit tests, watch off
pnpm test:int                        # integration; spins up a Postgres container
pnpm test:e2e                        # Playwright; needs pnpm dev running
pnpm lint && pnpm typecheck
pnpm contracts:gen                   # regenerate API types from openapi.yaml
pnpm contracts:check                 # fail if implementation and spec disagree
```

**Creating a migration**

```bash
# 1. write contracts/db/migrations/NNNN_description.sql by hand
# 2. apply it
pnpm db:migrate
# 3. update the Drizzle schema in packages/db to match
# 4. verify no drift
pnpm --filter @tnr/db check-schema
```

Migrations are hand-written and forward-only (ADR-0005). Never edit an applied migration; add a new one.

## 7. Testing offline behaviour locally

Chrome DevTools → Network → Offline works for the basics. For the flows that actually matter:

```bash
pnpm test:e2e --grep offline    # scripted offline scenarios
```

Manual checks worth doing before touching sync code:

1. Go offline, create 5 sightings with photos, kill the tab, reopen. All five must still be pending.
2. Come back online. Everything drains. No duplicates.
3. Throttle to Slow 3G and confirm capture still feels instant — the UI must never wait on the network.
4. Fill the storage quota (DevTools → Application → Storage) and confirm a graceful warning rather than a crash.

## 8. Working with PostGIS

```bash
psql postgresql://tnr:tnr@localhost:5432/tnr_dev
```

```sql
SELECT postgis_version();

-- packs within 2 km of Pitești centre (lon, lat — longitude FIRST)
SELECT name, ST_Distance(centroid, ST_MakePoint(24.8697, 44.8565)::geography) AS m
FROM pack
WHERE org_id = '...'
  AND ST_DWithin(centroid, ST_MakePoint(24.8697, 44.8565)::geography, 2000)
ORDER BY m;
```

Reminder that costs people hours: `ST_MakePoint` takes **longitude first**. A swapped pair puts Pitești in the
Indian Ocean.

## 9. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `extension "postgis" is not available` | Using `postgres:16` instead of `postgis/postgis:16-3.4`. Recreate the container |
| Port already allocated | Another project's containers. `pnpm infra:down`, or change ports in `.env` |
| Migrations fail after pulling `main` | Someone added a migration. `pnpm db:migrate`; if it still fails, `pnpm db:reset` |
| Web can't reach the API | `VITE_API_URL` mismatch, or the API crashed at boot on env validation — read its output |
| Service worker serving stale code | DevTools → Application → Service Workers → Unregister, then hard reload |
| OSRM returns 400 | Coordinates outside the Romania extract, or lat/lon swapped |
| `pnpm install` mismatch errors | `rm -rf node_modules **/node_modules && pnpm install` |
| Integration tests hang | A Testcontainers container failed to start; check Docker is running and has memory |

## 10. Editor setup

VS Code / Cursor recommended extensions are in `.vscode/extensions.json`: ESLint, Prettier, Tailwind IntelliSense,
Vitest, Playwright, an SQL formatter, and an `.env` syntax highlighter.

Workspace settings enable format-on-save with Prettier and ESLint auto-fix. Do not reformat files you did not
otherwise change (`AGENTS.md` §5) — formatting churn destroys reviewability for the next agent.
