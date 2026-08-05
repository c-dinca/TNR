# Infrastructure and DevOps

Constraints that shape everything here: **one operator**, **< €150/month until the third paying customer**
(`NFR-050`), **EU-only data residency** (`FR-124`), **99.5% write availability** (`NFR-020`).

The guiding rule: a solo founder must be able to understand the entire production system from memory at 3 a.m.

---

## 1. Environments

| Env | Purpose | Data | Deploy trigger |
|---|---|---|---|
| `local` | Development | Seeded synthetic | Manual, Docker Compose |
| `preview` | Per-PR verification | Ephemeral, seeded | Automatic on PR |
| `staging` | Pre-production, migration rehearsal | Anonymised or synthetic | Automatic on merge to `main` |
| `production` | Live | Real | Manual promotion from a green staging |

**Real customer data never leaves production.** Staging uses synthetic seed data or an anonymised extract produced
by a documented, tested script (`TNR-016`). No exceptions: this data includes locations that can identify
households.

## 2. Production topology

```
                         Cloudflare (DNS, TLS, WAF, caching)
                                      │
              ┌───────────────────────┼──────────────────────────┐
              ▼                       ▼                          ▼
    ┌──────────────────┐   ┌────────────────────┐   ┌─────────────────────┐
    │ web (static SPA) │   │ api (Fly, fra)     │   │ worker (Fly, fra)   │
    │ Cloudflare Pages │   │ 2 machines, 512 MB │   │ 1 machine, 1 GB     │
    └──────────────────┘   └─────────┬──────────┘   └──────────┬──────────┘
                                     │                         │
              ┌──────────────────────┼─────────────────────────┼───────────────┐
              ▼                      ▼                         ▼               ▼
   ┌────────────────────┐  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────┐
   │ PostgreSQL 16 +    │  │ Redis (Upstash   │  │ R2 (EU) media    │  │ OSRM + VROOM │
   │ PostGIS (managed,  │  │ EU / Fly Redis)  │  │ + PMTiles + PDFs │  │ (Fly, fra)   │
   │ EU, PITR)          │  └──────────────────┘  └──────────────────┘  └──────────────┘
   └────────────────────┘
```

Region: **Frankfurt (`fra`)**, single region. Every data-holding service is EU-resident, which a CI check enforces
against the infrastructure config (`NFR-036`).

Sizing rationale: `api` at 2×512 MB gives rolling deploys and survives one machine dying; it is stateless, so
scaling is a number change. `worker` gets 1 GB because Chromium PDF rendering and `sharp` are the memory-hungry
paths. OSRM for a Romania extract needs ~1 GB resident and is a separate machine so a routing OOM cannot take down
the API.

## 3. Cost envelope

| Component | Monthly (EUR) |
|---|---|
| Managed Postgres + PostGIS (EU, PITR) | 25–50 |
| api (2 × 512 MB) | 10–15 |
| worker (1 × 1 GB) | 8–12 |
| OSRM + VROOM (1 × 1 GB) | 8–12 |
| Redis (managed, small) | 0–10 |
| R2 storage + operations (zero egress) | 5–15 |
| Cloudflare Pages + DNS | 0 |
| Error tracking, uptime, log tail | 0–20 |
| **Total** | **~56–134** |

Within budget with headroom. The three most likely overruns are media egress (mitigated by R2's zero-egress
pricing, ADR-0009), Postgres storage growth from the audit and sighting tables, and Chromium-driven worker memory
forcing a larger machine.

## 4. Choice of platform

Fly.io was chosen for Phase 1 (ADR-0012). The reasoning, honestly stated: containers deploy in one command,
Frankfurt is available, scale-to-few is cheap, and there is no infrastructure team to operate an EKS cluster. The
cost is a smaller-vendor dependency and occasional platform flakiness.

That risk is bounded deliberately: everything ships as a plain Docker image with configuration entirely from the
environment, and no Fly-specific API is used from application code. Migrating to ECS, Cloud Run, or a Hetzner box
with Docker Compose is a deployment-manifest change, not a rewrite. Postgres is managed and portable; object
storage is S3-compatible.

Explicitly rejected for Phase 1: Kubernetes (operational cost far exceeds the benefit at three services),
serverless functions (a persistent connection pool and a worker pool fit badly), and a BaaS backend
(01-system-overview §10).

## 5. Infrastructure as code

```
infra/
  terraform/          Cloudflare DNS/WAF, R2 buckets + lifecycle, Fly apps, Postgres, secret wiring
    environments/{staging,production}/
    modules/{app,storage,database,dns}/
  fly/                fly.{api,worker,osrm}.toml
  docker/             Dockerfiles: api, worker, osrm-vroom
  compose/            docker-compose.yml for local
  scripts/            bootstrap, seed, anonymise, backup-verify, restore-drill
```

Rules: no console clicking — if it is not in Terraform, it does not exist. State in an R2 backend with locking.
`terraform plan` runs on every infra PR and the plan is posted to the PR. Apply is manual for production.

## 6. Containers

Multi-stage builds, distroless or `node:22-slim` runtime, non-root user, `dumb-init` as PID 1 for correct signal
handling, pinned base image digests, healthcheck defined in the image.

| Image | Size target | Contents |
|---|---|---|
| `api` | < 250 MB | Node 22 + compiled API |
| `worker` | < 700 MB | Node 22 + `sharp` + Chromium (PDF rendering) |
| `osrm-vroom` | < 1.5 GB | OSRM backend + VROOM + prebuilt Romania graph |

The OSRM graph is built once in CI from a pinned Romania OSM extract and baked into the image, so a deploy never
waits on a 20-minute extraction and a container restart is fast. Graph refresh is a deliberate, quarterly, tracked
action (`TNR-020`) rather than an implicit dependency on upstream OSM availability.

## 7. Configuration and secrets

All configuration comes from the environment and is validated at boot by a Zod schema (`NFR-032`). A missing or
malformed value **crashes at startup** — never at first use, three hours later, in a worker, in production.

```
NODE_ENV, APP_ENV, PORT, COMMIT_SHA
DATABASE_URL, DATABASE_POOL_MAX
REDIS_URL
S3_ENDPOINT, S3_REGION, S3_BUCKET_MEDIA, S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY
JWT_PRIVATE_KEY, JWT_PUBLIC_KEYS (JWKS-style set with kid), ACCESS_TOKEN_TTL_S, REFRESH_TOKEN_TTL_S
OSRM_URL, VROOM_URL
SMTP_URL or EMAIL_API_KEY, EMAIL_FROM
SENTRY_DSN, LOG_LEVEL
PMTILES_URL
CHIP_LOOKUP_ENABLED, CHIP_LOOKUP_RATE_PER_HOUR
FEATURE_FLAGS (comma-separated)
```

Secrets live in Fly secrets (production/staging) and `.env` (local, gitignored). They are never in source, never in
logs, never in error reports. Rotation procedure is documented per secret in the runbook; JWT signing keys support
overlapping validity so rotation needs no downtime.

## 8. Database operations

**Managed Postgres 16 with the PostGIS extension**, EU region, PITR enabled. Managed rather than self-hosted
because a solo founder should not own backup verification, failover and patching for the one component whose loss
is unrecoverable.

| Concern | Approach |
|---|---|
| Migrations | Forward-only numbered SQL, applied by a dedicated job before the app rollout |
| Backward compatibility | Every migration must work with the previously deployed app version (`NFR-026`) |
| Backups | Provider automated daily + PITR; RPO ≤ 15 min, RTO ≤ 4 h (`NFR-023`) |
| Restore rehearsal | Quarterly, documented, with the measured RTO recorded (`TNR-019`) |
| Connection pooling | Pool per instance, `DATABASE_POOL_MAX` sized to stay under the provider limit; PgBouncer only if measurements demand it |
| Roles | `tnr_app` (DML, no `UPDATE`/`DELETE` on `audit_event`), `tnr_migrate` (DDL), `tnr_readonly` (analytics) |
| Slow queries | `pg_stat_statements` enabled; anything > 500 ms is investigated |

The expand/contract discipline for migrations is mandatory and is what makes a five-minute rollback possible
(`NFR-045`):

```
1. Expand   — add the nullable column / new table. Deploy. Old code unaffected.
2. Migrate  — backfill in a batched job. Deploy code that writes both and reads new.
3. Contract — remove the old column in a LATER release, once rollback is no longer plausible.
```

Never rename a column in place. Never add a `NOT NULL` column without a default in one step. Never drop anything
in the same release that stopped using it.

## 9. Deployment

```
merge to main
  → CI: lint, typecheck, unit, integration (Postgres+PostGIS container), build images
  → deploy staging: migrate → api rolling → worker → web
  → smoke tests on staging
  → manual promotion to production
  → production: migrate → api rolling (health-gated) → worker → web
  → post-deploy smoke + error-rate watch for 15 min
```

Rolling deploys with health gates. Rollback is redeploying the previous image tag: ≤ 5 minutes, no database
restore (`NFR-045`) — which is exactly what expand/contract buys.

Deploys are avoided during known campaign windows (a mobile clinic day), because although field capture survives
an outage, a coordinator mid-planning does not enjoy one. Field clients keep working offline through any deploy
(`NFR-025`), which is the real maintenance strategy.

## 10. Static frontend

Built by CI, deployed to Cloudflare Pages. Cache policy: immutable hashed assets with a long TTL; `index.html` and
the service worker with `no-cache`. A stale service worker serving a new API is the classic PWA failure, so
`X-TNR-Min-Client` (`NFR-015`) exists as the backstop.

## 11. Job processing

BullMQ on Redis, one worker process, named queues with distinct concurrency:

| Queue | Concurrency | Retries | Notes |
|---|---|---|---|
| `cluster-sighting` | 4 | 5, exponential | Advisory lock per org |
| `process-media` | 2 | 3 | Memory-bound (`sharp`) |
| `optimise-mission` | 2 | 2 | Calls OSRM/VROOM |
| `generate-report` | 1 | 2 | Chromium, memory-bound |
| `build-evidence` | 1 | 2 | Streams archives |
| `lookup-microchip` | 1 | 3 | Externally rate-limited |
| `refresh-metrics` | 1 | 3 | Scheduled, every 5 min |
| `retention-sweep` | 1 | 1 | Scheduled, nightly |
| `verify-audit-chain` | 1 | 1 | Scheduled, nightly |
| `gc-orphan-media` | 1 | 1 | Scheduled, nightly, with a sanity threshold |

Jobs must be idempotent — a retry after a partial success must not double-write. Terminal failures land in a
dead-letter view surfaced in the admin UI (`NFR-047`), and `job_record` mirrors state into Postgres so a Redis
flush does not erase operational history.

Redis is treated as **disposable**: losing it costs in-flight jobs, not data. Derivations are re-triggerable from
source, which is why nothing durable ever lives only in Redis.

## 12. Backup and disaster recovery

| Asset | Mechanism | RPO | RTO |
|---|---|---|---|
| Postgres | Managed daily + PITR | 15 min | 4 h |
| Media (R2) | Versioning, 30 days | ~0 | minutes |
| Reports/evidence | Regenerable from source | n/a | job runtime |
| Redis | None (disposable) | n/a | n/a |
| IaC | Git | n/a | minutes |
| Secrets | Password manager, documented | n/a | minutes |

Runbook scenarios, each rehearsed and documented (`TNR-019`): accidental table drop, region outage, media bucket
misconfiguration, compromised credential, corrupted audit chain, expired TLS certificate.

The quarterly restore drill is non-negotiable. An unverified backup is a belief, not a backup.

## 13. Domains

| Host | Purpose |
|---|---|
| `app.tnr-os.dev` | Web app (field + console) |
| `api.tnr-os.dev` | API |
| `tiles.tnr-os.dev` | PMTiles via R2 + Cloudflare cache |
| `media.tnr-os.dev` | Signed media URLs |
| `status.tnr-os.dev` | Public status page |

TLS terminated at Cloudflare, HSTS enabled, TLS 1.2+ (`NFR-031`).

## 14. Scaling path

Ordered by when it will actually be needed:

1. `api` machines 2 → 4 (stateless, trivial).
2. Split the worker pool: media/PDF (memory) apart from clustering/metrics (CPU).
3. Postgres read replica for reporting and metric refresh.
4. Partition `sighting` and `audit_event` by month.
5. A second region only if a non-EU customer with residency requirements appears — which would be a strategy
   change, not a scaling event.

Nothing in this list requires re-architecture. That is the point of §2 being as small as it is.

## 15. Open questions

> **OQ-INFRA-1** — Managed Postgres provider: Neon (branching, generous free tier, PostGIS support) versus Fly
> Postgres (co-located, but self-operated) versus Supabase (PostGIS plus storage, more lock-in). Decide before
> `TNR-002`. Criteria: PostGIS 3.4+, EU region, PITR, connection limits, and cost at 50 GB.

> **OQ-INFRA-2** — Is Chromium in the worker image worth 300 MB, or should PDF rendering be a separate small
> service? Decide after measuring worker memory under a real report load.
