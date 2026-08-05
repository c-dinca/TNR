# ADR-0010: BullMQ on Redis for asynchronous work

- **Status**: Accepted
- **Date**: 2026-08-05
- **Affects**: `apps/worker`, `infra/`

## Context

Several operations must not sit on an interactive request path: pack clustering after sync (`NFR-002` demands a
500 ms sync response), image derivatives, route optimisation, PDF and evidence-pack generation, chip lookup,
metric refresh, and scheduled retention and verification sweeps.

Requirements: visible job state for the UI (`NFR-064`), bounded retries with a dead-letter view (`NFR-047`),
per-queue concurrency control because some jobs are memory-bound, and scheduled jobs.

## Options considered

### Option A — `pg-boss` (Postgres-backed queue)

**For:** No new infrastructure; jobs enqueue in the same transaction as the domain change, which elegantly
eliminates the enqueue-after-commit race; one backup covers everything.
**Against:** Job polling load lands on the one database that field sync depends on; per-queue concurrency and rate
limiting are less developed; a job storm competes with interactive queries for the resource we least want to
saturate. Genuinely the closest alternative, and rejected mainly to keep the database's latency profile
predictable.

### Option B — SQS / cloud-native queue

**For:** Fully managed, effectively infinite scale.
**Against:** Another vendor; no built-in scheduling or job-state querying; poor local development story; latency
that is irrelevant to us but complexity that is not.

### Option C — Temporal

**For:** Excellent for long-running, multi-step workflows with durable state.
**Against:** Very heavy operationally for one person. Our jobs are single-step, short, and retry-safe. This is
solving a workflow-orchestration problem we do not have.

### Option D — BullMQ on Redis

**For:** Mature, TypeScript-native, per-queue concurrency and rate limits, delayed and repeatable jobs, retries
with backoff, a usable dashboard; trivial in local Docker Compose; Redis is cheap or free at our scale.
**Against:** Another service to run; Redis persistence is weaker than Postgres, so an unlucky flush loses in-flight
jobs; job state lives outside the main database unless mirrored.

## Decision

**Option D.** BullMQ on Redis, with two mitigations for its weaknesses:

1. **`job_record` in Postgres mirrors job state** ([`../02-architecture/02-data-model.md`](../02-architecture/02-data-model.md)
   §3.14), so the UI can show honest status and operational history survives a Redis flush.
2. **Every job is idempotent and re-triggerable from source data.** Redis is treated as disposable: losing it costs
   in-flight work, never data. Nothing durable exists only in Redis.

Queues, concurrencies and retry policies are tabulated in
[`../02-architecture/09-infrastructure-and-devops.md`](../02-architecture/09-infrastructure-and-devops.md) §11.

## Consequences

**Positive** — interactive paths stay fast; memory-bound jobs (PDF, image) get their own concurrency limits so they
cannot starve clustering; scheduled jobs need no external cron; excellent local development experience.

**Negative** — one more service to operate and monitor; the enqueue-after-commit race must be handled explicitly
(enqueue only after the transaction commits, and make the job tolerate a missing row); job state lives in two
places, so the mirror must be kept honest.

**Neutral** — moving to `pg-boss` later would be contained, since job handlers are plain functions over the domain
services.

## Revisit when

Redis operational cost or an incident caused by job-state divergence outweighs the database-isolation benefit. If
that happens, `pg-boss` is the fallback and the handlers port largely unchanged.
