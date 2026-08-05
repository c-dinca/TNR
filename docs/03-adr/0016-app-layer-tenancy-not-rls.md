# ADR-0016: Application-layer tenancy instead of row-level security

- **Status**: Accepted
- **Date**: 2026-08-05
- **Affects**: `packages/db`, every repository, the test suite

## Context

Cross-tenant leakage is the worst non-integrity failure this product can have. The data includes precise stray-dog
locations, which in the wrong hands enables poisoning
([`../02-architecture/11-security-and-gdpr.md`](../02-architecture/11-security-and-gdpr.md) §1). An NGO must be
certain another org — possibly a municipal culling contractor — cannot see its packs.

Requirements: `FR-030`–`FR-033`, `NFR-030`.

## Options considered

### Option A — Postgres row-level security

Policies on every table restricting rows by a session variable holding the current org.

**For:** Defence in depth at the database itself; a forgotten `WHERE` clause cannot leak; the guarantee survives an
application bug.
**Against:** Every connection must set the session variable correctly, and a pooled connection that leaks state
between requests is a subtle, severe failure — the classic PgBouncer-plus-RLS footgun. Workers legitimately operate
across orgs with a system identity, which means either policy exemptions (weakening the guarantee) or contorted
context switching. Policy debugging is opaque: a query silently returns zero rows and the developer cannot easily
see why. Policies also add per-query planning overhead on the hottest paths.

### Option B — Application-layer scoping with mandatory `OrgContext`

Every repository method takes an `OrgContext` as its first parameter; a repository function without one does not
typecheck. Every tenant query filters `org_id`. Verified by an adversarial test suite covering every route.

**For:** Explicit and debuggable; workers use the same mechanism with an explicit `SystemContext` naming the org;
no pooling hazard; no per-query overhead; failures are visible in code review as a missing parameter.
**Against:** A forgotten filter in a hand-written query is possible; the guarantee rests on test coverage and lint
discipline rather than on the database.

### Option C — Both

**For:** Maximum assurance.
**Against:** All of RLS's operational complexity plus the application work, at a stage where it would slow every
feature. Better sequenced than skipped.

## Decision

**Option B for Phase 1**, with the schema deliberately shaped so RLS can be added later without migration (every
tenant table has a uniform, non-nullable `org_id`).

The assurance comes from three mechanisms working together:

1. **Type-level** — `OrgContext` is a required first parameter; a tenant query cannot be constructed without one.
2. **Lint-level** — a rule flags `org_id` read from `body`, `query` or `params`, and bans string-concatenated SQL.
3. **Test-level** — a suite generated from the OpenAPI route list attempts cross-org access on **every** endpoint
   and verb, and **fails CI when a new endpoint is not covered** (`NFR-030`). Forgetting is not possible; the
   coverage is measured against the route list rather than written by hand.

## Consequences

**Positive** — explicit, debuggable scoping; workers are handled cleanly with `SystemContext`; no connection-pooling
hazard; no query overhead; a missing scope is visible in review.

**Negative** — the database does not enforce isolation, so a hand-written raw query could leak; the guarantee
depends on the adversarial suite remaining exhaustive, which makes that suite production-critical code; a
sufficiently creative bug could evade all three layers.

**Neutral** — adding RLS later is a migration adding policies, not a schema change. The uniform `org_id` column is
the seam.

## Revisit when

The first customer with a formal security review demands database-level enforcement, or an incident or near-miss
shows the application layer is insufficient. Adding RLS as defence in depth is the planned response, not a
redesign.
