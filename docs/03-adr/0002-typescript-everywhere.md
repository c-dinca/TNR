# ADR-0002: TypeScript across client, API and workers

- **Status**: Accepted
- **Date**: 2026-08-05
- **Affects**: every package

## Context

The founder is a full-stack engineer working alone, assisted by AI agents. The offline client and the server must
agree exactly on validation rules — a mutation validated on a phone and rejected by the server a week later, in a
village, is a data-loss event from the user's point of view (`05-offline-first-and-sync.md` §3).

## Options considered

### Option A — TypeScript client, Go or Rust API

**For:** Better raw performance, lower memory, excellent concurrency. Go in particular is a fine fit for a small
API.
**Against:** Validation logic must be written twice and kept in sync by discipline — precisely the failure mode
that costs field data. Two toolchains, two dependency ecosystems, two idioms for agents to hold. The performance
advantage is irrelevant when the bottleneck is Postgres and a 2G radio.

### Option B — TypeScript client, Python API

**For:** Best ML ecosystem, and ML is on the roadmap.
**Against:** Same duplication problem. The ML work is deferred (ADR-0017) and, when it arrives, it is a separate
containerised service that can be Python without the API being Python.

### Option C — TypeScript everywhere

**For:** One language, one toolchain, one dependency graph. Zod schemas are shared literally — the same object
validates on the device and on the server. Types generated from OpenAPI are consumed directly. Agents context-switch
less and produce more consistent code.
**Against:** Node's CPU-bound performance is mediocre; `sharp` and Chromium in the worker are heavy; runtime type
safety requires discipline because TypeScript erases at runtime.

## Decision

**Option C.** TypeScript with `strict: true` everywhere, Node 22 LTS.

`any` is banned (`AGENTS.md` §4). Runtime validation at every boundary via Zod — types alone guarantee nothing
about data arriving from a three-month-old client.

## Consequences

**Positive** — validation logic exists once; a change to a sighting schema updates the device, the server and the
generated types in one commit; agents work in one idiom.

**Negative** — CPU-heavy work (image derivatives, PDF rendering) is slower and memory-hungrier than a compiled
language, which is why the worker gets a 1 GB machine; Node's ecosystem churn requires disciplined dependency
management.

**Neutral** — a future ML service will be Python, invoked over HTTP from the worker. That is a service boundary,
not a violation of this decision.

## Revisit when

A CPU-bound path becomes a measured bottleneck that caching cannot fix. The realistic candidate is image
processing at very high volume, which would become a small separate service rather than a language change.
