# ADR-0004: REST with OpenAPI rather than GraphQL

- **Status**: Accepted
- **Date**: 2026-08-05
- **Affects**: `contracts/openapi.yaml`, `apps/api`, `apps/web`

## Context

One first-party client, offline-first, with a batching write path. Client versions in the field may be months old
and hold a week of queued mutations (`NFR-015`). Third-party API consumers are not planned for Phase 1.

The contract must be stable, inspectable, cacheable, and safe to evolve additively.

## Options considered

### Option A — GraphQL

**For:** Flexible querying; the console's varied views could fetch exactly what they need; a single endpoint;
strong tooling.
**Against:** Offline batching fits badly — our `/v1/sync` needs per-mutation partial success, which is awkward in a
GraphQL mutation list. HTTP caching and CDN behaviour are worse. Query-cost control against a hostile or naive
client is real work. Idempotency keys, `Retry-After` and problem documents are HTTP-native concepts we would be
reimplementing. And the main benefit — many clients with divergent needs — does not apply when there is one client.

### Option B — tRPC

**For:** Zero-codegen end-to-end types in a TypeScript monorepo.
**Against:** Assumes client and server versions move together. Ours cannot: a phone may run a three-month-old build.
A published, versioned, inspectable contract is a requirement, not a nicety.

### Option C — REST described by OpenAPI 3.1

**For:** HTTP semantics we already need (status codes, `Retry-After`, conditional requests, idempotency headers,
RFC 9457 problem documents). The spec is a durable artefact a funder's technical reviewer could read. Client types
are generated from it; a drift check fails CI. Additive evolution is well understood.
**Against:** Over- and under-fetching on complex console screens; the spec must be maintained alongside the code
or it rots; no built-in query flexibility.

## Decision

**Option C.** REST under `/v1`, described by a normative `contracts/openapi.yaml`, with client types generated
from the spec and a CI check that the implementation matches.

Over-fetching is handled with purpose-built read endpoints (for example `GET /v1/metrics/campaign/{id}`) rather
than a generic query language. Specific endpoints for specific screens are easier to optimise, cache and reason
about than a general query surface.

## Consequences

**Positive** — offline batching, idempotency and partial success are expressible naturally; the contract is a real
artefact; caching and rate limiting work with the platform rather than around it; a stale client keeps working.

**Negative** — the spec can drift from the code without the CI check, making that check load-bearing; new console
views may need new endpoints rather than a new query; some responses carry fields a given screen does not use.

**Neutral** — a GraphQL gateway could be layered on later if a third-party integrator ever needs one.

## Revisit when

A second, materially different client appears (a funder portal with very different data needs), or external
integrators arrive with divergent query requirements.
