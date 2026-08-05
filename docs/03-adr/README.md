# Architecture Decision Records

An ADR records **why an alternative was rejected**. It is not a changelog and not a design document.

## Rules

1. Once `Accepted`, an ADR is immutable. To change a decision, write a new ADR and mark the old one
   `Superseded by ADR-XXXX`.
2. Every ADR must list options actually considered, with the real trade-off — not a straw man.
3. Consequences must include the negative ones. An ADR with only upsides was not a decision.
4. Number sequentially. Never reuse a number.

## Index

| ADR | Title | Status |
|---|---|---|
| [0000](0000-template.md) | Template | — |
| [0001](0001-modular-monolith-monorepo.md) | Modular monolith in a pnpm monorepo | Accepted |
| [0002](0002-typescript-everywhere.md) | TypeScript across client, API and workers | Accepted |
| [0003](0003-nestjs-on-fastify.md) | NestJS on Fastify for the API | Accepted |
| [0004](0004-rest-over-graphql.md) | REST with OpenAPI rather than GraphQL | Accepted |
| [0005](0005-postgres-postgis-drizzle.md) | PostgreSQL + PostGIS with Drizzle and SQL migrations | Accepted |
| [0006](0006-offline-first-pwa-outbox.md) | Offline-first PWA with a client outbox, not CRDTs | Accepted |
| [0007](0007-maplibre-pmtiles.md) | MapLibre with self-hosted PMTiles | Accepted |
| [0008](0008-own-auth-jwt-refresh.md) | Own authentication with JWT access and rotating refresh tokens | Accepted |
| [0009](0009-s3-compatible-media-r2.md) | S3-compatible object storage on Cloudflare R2 | Accepted |
| [0010](0010-bullmq-redis-jobs.md) | BullMQ on Redis for asynchronous work | Accepted |
| [0011](0011-self-hosted-osrm-vroom.md) | Self-hosted OSRM + VROOM for routing | Accepted |
| [0012](0012-fly-io-eu-hosting.md) | Containers on Fly.io Frankfurt, EU-only residency | Accepted |
| [0013](0013-no-recs-integration.md) | No RECS integration; parallel operational registry | Accepted |
| [0014](0014-hash-chained-audit-log.md) | Hash-chained audit log for donor-grade evidence | Accepted |
| [0015](0015-uuidv7-client-generated-ids.md) | Client-generated UUIDv7 primary keys | Accepted |
| [0016](0016-app-layer-tenancy-not-rls.md) | Application-layer tenancy instead of row-level security | Accepted |
| [0017](0017-defer-ml-notch-detection.md) | Defer ear-notch ML; build the seam and the corpus | Accepted |
| [0018](0018-append-only-interventions.md) | Append-only interventions with supersede corrections | Accepted |
