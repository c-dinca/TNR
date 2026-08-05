# ADR-0006: Offline-first PWA with a client outbox, not CRDTs or a sync engine

- **Status**: Accepted
- **Date**: 2026-08-05
- **Affects**: `apps/web`, `/v1/sync`

## Context

Volunteers work in Romanian villages with 2G, EDGE, or no coverage, on cheap Android phones. Losing a volunteer's
data once loses the volunteer. Requirements: `FR-024`–`FR-027`, `NFR-010`–`NFR-018`.

Two questions: what client platform, and what sync model.

## Options considered

### Platform

**Native iOS + Android** — best offline primitives, background sync, reliable local storage.
Rejected: two codebases plus a web console for a solo founder; app-store release latency; and PWA capabilities
meet the actual requirements. Revisit only if push notifications or BLE force it (Phase 2).

**React Native / Expo** — one mobile codebase, good offline story, OTA updates.
Rejected: still a second codebase alongside the console, plus a native build pipeline. The console is
desktop-first and would not share much. Genuinely the closest call here.

**PWA** — one codebase, instant updates, no store, installable, works on any device a volunteer already owns.
Weaker iOS support (no background sync, capped storage) and no true background execution.

### Sync model

**CRDTs (Yjs/Automerge)** — automatic conflict-free merge.
Rejected: sightings and interventions are append-only observations, not collaboratively edited documents. There is
nothing to merge. A CRDT runtime would add bundle weight (fighting `NFR-004`), a difficult debugging surface, and
opaque conflict semantics — for a problem we do not have.

**A sync-engine service (ElectricSQL, PowerSync, Replicache)** — replication as a solved product.
Rejected: they replicate a data model; ours needs per-mutation business validation, authorisation, hash-chained
audit and partial-batch success. Bending a general engine into that is harder than the outbox, and it puts a
third-party dependency on the most critical path in the product.

**Client outbox with idempotency keys** — a durable queue of mutations replayed against a batch endpoint that
returns per-mutation results.
Simple, debuggable, and exactly the semantics the domain has.

## Decision

**PWA with a Dexie/IndexedDB outbox, replayed against `POST /v1/sync` with per-mutation idempotency keys and
partial success.**

Conflict handling is domain-specific rather than generic (`05-offline-first-and-sync.md` §6): append-only where
possible, last-write-wins by `occurred_at` for stop outcomes, server-authoritative with optimistic version checks
for coordinator curation.

## Consequences

**Positive** — one codebase; the sync path is a few hundred lines an agent can read and reason about; conflict
rules are explicit and testable per entity; no third-party dependency on the critical write path; small bundle.

**Negative** — we own correctness of the queue, so its test suite (`05-offline-first-and-sync.md` §10) is
load-bearing; iOS Safari limits background sync, so drains are in-app only; IndexedDB storage quotas must be
handled explicitly; a Dexie schema migration on a device holding pending data is a data-loss risk requiring
careful testing.

**Neutral** — a native wrapper could be added later without changing the sync protocol.

## Revisit when

iOS becomes a significant share of field devices and its PWA limitations demonstrably cost data, or Phase 2 trap
alerts require push notifications that PWAs cannot deliver reliably enough.
