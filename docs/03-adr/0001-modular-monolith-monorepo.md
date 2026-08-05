# ADR-0001: Modular monolith in a pnpm monorepo

- **Status**: Accepted
- **Date**: 2026-08-05
- **Affects**: repo structure, CI, deployment

## Context

One founder, no team. Three deployable units (api, worker, web) sharing a domain model, validation schemas and
generated API types. The system must be operable by one person at 3 a.m. and understandable by AI agents working
concurrently on different areas.

Constraints: `NFR-046` (one command brings up everything locally), `NFR-050` (< €150/month), and the practical
need for several agents to work in parallel without stepping on each other.

## Options considered

### Option A — Microservices, one repo each

Independent deploy cadence, clear ownership, technology freedom per service.

**For:** Scales to many teams; blast radius per service is small.
**Against:** Distributed transactions across sightings, packs and audit events; six pipelines; six sets of
secrets; cross-repo type drift; no team to justify any of it. The audit chain in particular requires a domain
change and its audit event in one transaction — across services that becomes a saga for no benefit.

### Option B — Single application, single package

Simplest possible.

**For:** No build orchestration.
**Against:** No enforced boundaries. Frontend and backend code intermingle, shared types are copied, and
concurrent agents collide constantly because nothing declares ownership.

### Option C — Modular monolith in a monorepo (pnpm workspaces + Turborepo)

One repo, several packages, hard internal boundaries enforced by lint rules and package dependencies. `api` and
`worker` share one domain layer and deploy as separate processes from the same image.

**For:** One transaction boundary for domain + audit; shared types are a real dependency, not a copy; agent
ownership maps onto packages (`AGENTS.md` §9); Turborepo caches make CI fast; each package can still become a
service later.
**Against:** Build orchestration to learn; a careless import can cross a boundary unless lint enforces it; the
whole repo rebuilds if the shared package changes.

## Decision

**Option C.** Modular monolith in a pnpm workspace monorepo with Turborepo, deploying `api` and `worker` as
separate processes from a shared codebase.

Boundaries are enforced mechanically: `eslint-plugin-boundaries` prevents `apps/web` from importing
`apps/api`, prevents `packages/db` from importing HTTP types, and prevents controllers from importing
repositories.

## Consequences

**Positive** — one `pnpm install`; atomic changes across API and client; shared Zod schemas validate identically
on both sides; agents get clean ownership zones; CI caching keeps feedback fast.

**Negative** — Turborepo is another tool to understand; a shared-package change invalidates broad cache entries; a
runaway import can couple things that should stay apart, so the lint boundary config is load-bearing and must be
reviewed like production code.

**Neutral** — extracting a service later means moving a package and adding a transport, which is real work but
bounded.

## Revisit when

A second engineer joins with a genuinely independent deploy cadence, or one component's scaling profile diverges
sharply — the media/PDF worker is the most likely candidate.
