# ADR-0011: Self-hosted OSRM + VROOM for route optimisation

- **Status**: Accepted
- **Date**: 2026-08-05
- **Affects**: `apps/worker`, `infra/docker/osrm-vroom`

## Context

Route optimisation is the feature that pays for the subscription: NGOs burn enormous fuel budgets on empty vehicle
kilometres in remote villages. The problem is a capacitated VRP with a depot, a time window and cage capacity as
the binding constraint (`FR-073`, `04-geospatial-and-routing.md` §4).

Typical size is 5–25 stops, occasionally 60. Re-optimisation is frequent: a coordinator adjusts a plan several
times while building it. A 25-stop distance matrix is 625 elements, and it may be computed many times per mission.

## Options considered

### Option A — Google Routes / Distance Matrix API

**For:** Best road data, live traffic, no infrastructure.
**Against:** Per-element pricing. Frequent re-optimisation across many missions makes this a top-three cost line
against a €150/month budget (`NFR-050`). Terms also restrict storing results, which conflicts with caching a
matrix we will reuse.

### Option B — Mapbox Optimization API

**For:** Solves the VRP directly, reasonable pricing.
**Against:** Per-request cost that scales with the usage we want to encourage; a stop limit that constrains larger
missions; the same storage-restriction problem.

### Option C — Great-circle distance with a heuristic solver

**For:** Free, trivial, no infrastructure.
**Against:** Romania has mountains, rivers and unpaved roads. Straight-line ordering can be badly wrong, and a plan
the field team quietly ignores is worse than no plan — it destroys trust in the product's core promise. Acceptable
only as a clearly labelled fallback (`FR-075`).

### Option D — Self-hosted OSRM + VROOM

OSRM computes the road-network duration matrix; VROOM solves the capacitated VRP over it.

**For:** No marginal cost per optimisation, so re-optimisation is free and coordinators can iterate; real road
network from OSM; VROOM handles capacity, time windows, skills and multi-vehicle (the last is a future parameter
change, not a new integration); results are ours to cache indefinitely.
**Against:** One more container to run (~1 GB resident for a Romania graph); we own the OSM graph refresh; no live
traffic data; cold start requires the prebuilt graph.

## Decision

**Option D.** OSRM and VROOM in a single container, with the Romania OSM graph built in CI and baked into the
image.

Baking the graph avoids a 20-minute extraction on every container start and removes a deploy-time dependency on
upstream OSM availability. Graph refresh is a deliberate quarterly task (`TNR-020`).

The matrix is cached in Redis by rounded coordinate pair with a 30-day TTL. Pack centroids barely move, so hit
rates across re-optimisations are high.

Degraded mode is nearest-neighbour over great-circle distance, labelled `fallback_straight_line` everywhere it is
shown (`FR-075`). Honest labelling matters: presenting a straight-line order as optimised would be worse than
offering nothing.

## Consequences

**Positive** — zero marginal optimisation cost, so coordinators can iterate freely; real road distances, which is
what makes the fuel-saving claim defensible; multi-vehicle optimisation is already available in the engine when we
want it; results are freely cacheable.

**Negative** — a 1.5 GB image and a 1 GB machine; we own graph currency, and a stale graph means stale roads; no
traffic data (largely irrelevant for rural Romania); OSRM tuning is specialised knowledge if performance
disappoints.

**Neutral** — because the routing engine sits behind an interface with a fallback, swapping to a commercial API
later is contained.

## Revisit when

Optimisation latency misses `NFR-006` at real stop counts, or coverage expands beyond a region we can maintain a
graph for.
