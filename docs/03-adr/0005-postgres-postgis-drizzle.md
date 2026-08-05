# ADR-0005: PostgreSQL + PostGIS with Drizzle and hand-written SQL migrations

- **Status**: Accepted
- **Date**: 2026-08-05
- **Affects**: `packages/db`, `contracts/db/migrations/`

## Context

The domain is fundamentally geospatial: proximity clustering, viewport queries, polygon containment for locality
aggregation, and distance calculations. It also demands strict transactional integrity — a domain change and its
audit event must commit atomically (`FR-102`).

## Options considered

### Database

**MongoDB with geospatial indexes** — flexible documents, `$near` queries. Rejected: no real transactional
guarantee across the audit chain without significant care, weaker spatial capability than PostGIS (no polygon
containment against complex multipolygons at useful speed), and reporting aggregations become application code.

**PostgreSQL + PostGIS** — the reference implementation for open-source geospatial. `ST_DWithin` on `geography`
gives index-accelerated metre-based proximity; `ST_ClusterDBSCAN` gives server-side clustering; full ACID for the
audit chain; one database for relational, spatial and JSON needs.

**SQLite/LiteFS with SpatiaLite** — attractively cheap. Rejected: SpatiaLite is materially weaker than PostGIS,
concurrent write throughput is limited, and managed backup/PITR options are poor.

### ORM

**Prisma** — best DX, excellent migrations. Rejected: PostGIS types are unsupported, forcing `Unsupported()`
columns and raw queries for exactly the queries that matter most, which loses the type safety that was the
attraction.

**TypeORM** — mature, has some spatial support. Rejected: heavy, the migration story is fragile, and the
active-record/data-mapper duality invites inconsistent code from concurrent agents.

**Drizzle** — SQL-first, thin, fully typed, custom column types (so `geography` is a first-class typed column),
composes cleanly with raw SQL where needed.

**Raw `pg` with query builders** — maximum control, minimum safety. Rejected: too easy for an agent to write an
unparameterised query or forget the `org_id` filter.

### Migrations

**ORM-generated** — convenient, but generated DDL for PostGIS types, partial indexes and expand/contract sequences
is unreliable, and a generated migration is hard to review for the safety properties we care about (`NFR-026`).

**Hand-written numbered SQL** — fully explicit, reviewable, portable, and forces the author to think about lock
behaviour on a live table.

## Decision

**PostgreSQL 16 + PostGIS 3.4, Drizzle ORM, hand-written forward-only numbered SQL migrations.**

Drizzle for typed queries and composition; raw SQL through Drizzle's `sql` template for complex spatial work;
migrations as reviewed SQL files that are never edited after being applied anywhere.

## Consequences

**Positive** — best-in-class spatial capability; one database for everything; full transactional integrity for the
audit chain; migrations are explicit and reviewable; typed queries without an ORM's abstraction leaking into the
domain.

**Negative** — writing migrations by hand is slower and requires real SQL competence from every agent; Drizzle is
younger than Prisma with a smaller ecosystem; developers must understand PostGIS function semantics (notably that
`ST_Distance` in a `WHERE` clause cannot use the index).

**Neutral** — schema is defined twice, in migration SQL and in Drizzle's schema objects. A CI check compares them
against a migrated database, so drift is caught rather than prevented.

## Revisit when

Sighting or audit volume forces partitioning (expected around 5M rows), or reporting load justifies a read
replica. Neither changes this decision; both are extensions of it.
