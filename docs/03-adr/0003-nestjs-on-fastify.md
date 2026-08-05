# ADR-0003: NestJS on Fastify for the API

- **Status**: Accepted
- **Date**: 2026-08-05
- **Affects**: `apps/api`, `apps/worker`

## Context

The API needs consistent cross-cutting behaviour that must never be forgotten on a new endpoint: org scoping,
idempotency, audit interception, problem-json error mapping, permission checks. Multiple AI agents will add
endpoints concurrently, so the framework's job is to make the correct thing the default and the incorrect thing
awkward.

The worker must call the same services with the same dependency graph but no HTTP.

## Options considered

### Option A — Fastify alone, hand-rolled structure

**For:** Fastest, smallest, no magic; total control.
**Against:** Every project convention becomes a convention rather than a constraint. With concurrent agents, "remember
to add the org guard" is not a strategy — it is a future cross-tenant leak. Dependency wiring for a shared
service layer between API and worker becomes hand-written and drifts.

### Option B — Express

**For:** Ubiquitous, every agent has seen it.
**Against:** Slower, weaker TypeScript story, same structural problem as A, and the ecosystem is drifting away.

### Option C — NestJS on the Fastify adapter

Opinionated modules, DI, guards, interceptors, pipes, over a Fastify HTTP layer.

**For:** Cross-cutting concerns become guards and interceptors applied globally — an agent cannot forget the audit
interceptor because it is not per-endpoint code. DI lets the worker instantiate the same services without HTTP.
Module layout is uniform, so an agent can navigate a module it has never read. Fastify keeps the throughput.
**Against:** Decorator-heavy, a real learning curve, more boilerplate per module, and DI makes some stack traces
harder to follow. Nest's own conventions occasionally fight ours (we validate with Zod, not `class-validator`).

### Option D — tRPC

**For:** End-to-end type safety with no code generation.
**Against:** Our client is offline-first with a batching outbox and long-lived old versions; a stable, versioned,
inspectable HTTP contract matters more than inferred types (ADR-0004). tRPC also assumes a matched client/server
pair, which is exactly what we cannot assume.

## Decision

**Option C.** NestJS with the Fastify adapter.

Zod for validation via a custom pipe, not `class-validator` — one validation library shared with the client
(ADR-0002). Module file layout is fixed (`01-system-overview.md` §4) so every module looks the same.

Global cross-cutting pieces: `OrgScopeGuard`, `PermissionsGuard`, `IdempotencyInterceptor`,
`AuditInterceptor`, `ProblemJsonExceptionFilter`.

## Consequences

**Positive** — a new endpoint gets tenancy, permissions, idempotency and audit by default; the worker reuses the
service layer through DI; uniform structure is ideal for agents; testability is good because everything is
injected.

**Negative** — more ceremony than Fastify alone; decorator metadata and DI complicate some debugging; Nest's
defaults must be actively overridden in places (validation, error format); a heavier dependency to keep current.

**Neutral** — moving off Nest later would mean rewriting wiring, not domain logic, since services hold no
framework types.

## Revisit when

Cold-start time or memory becomes a measured constraint, or Nest's release cadence becomes a maintenance burden
disproportionate to its benefit.
