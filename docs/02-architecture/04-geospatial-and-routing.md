# Geospatial design and route optimisation

Geography is the product. This document covers the coordinate conventions, PostGIS usage, pack clustering
algorithm, route optimisation pipeline, and map rendering including offline tiles.

---

## 1. Coordinate conventions

| Rule | Value |
|---|---|
| CRS | WGS84, EPSG:4326, everywhere. No projected CRS in storage |
| Column type | `geography`, not `geometry` — distances come out in metres without projection gymnastics |
| Axis order | **longitude first** in all JSON and function arguments: `[lon, lat]`, `ST_MakePoint(lon, lat)` |
| Precision | 6 decimal places (~11 cm), locale-independent |
| Accuracy | always stored alongside a captured point (`location_accuracy_m`) |

Axis order is the number-one source of silent geospatial defects. Mitigations: a single shared
`Point` Zod schema used by every DTO, a helper `makePoint(lon, lat)` with named parameters at the repository
boundary, and a test asserting a known Romanian coordinate lands inside Romania (a swapped pair lands in the
Indian Ocean, which the test catches loudly).

## 2. PostGIS usage

Required extensions: `postgis` (3.4+). We do not need `postgis_topology` or raster support.

**Distance and proximity** — always `ST_DWithin` on `geography`, which uses the GIST index:

```sql
SELECT id FROM pack
WHERE org_id = $1
  AND deleted_at IS NULL
  AND ST_DWithin(centroid, ST_MakePoint($2, $3)::geography, $4);
```

Never `ST_Distance(a, b) < x` in a `WHERE` clause — it cannot use the index and turns a map pan into a table
scan.

**Viewport** — `ST_MakeEnvelope(minLon, minLat, maxLon, maxLat, 4326)::geography` with `&&` then `ST_Intervals`
as needed; the bbox operator is index-accelerated.

**Server-side clustering** above the feature cap uses `ST_ClusterDBSCAN` over the viewport result set, returning
cluster centroids and counts (`NFR-008`).

**Locality assignment** — `ST_Contains(locality.geometry, pack.centroid)` in a nightly job, not on the write
path. Containment against multipolygons is too expensive for interactive sync.

**Centroid** — `ST_Centroid(ST_Collect(location))` over the pack's recent sightings, weighted by recency in the
service layer rather than in SQL (weighting logic belongs in code where it is testable).

## 3. Pack clustering

### 3.1 Purpose

Turn a stream of independent field pins into stable planning units. Coordinators must never be handed 400 loose
dots (`FR-040`–`FR-042`).

### 3.2 Algorithm (Phase 1)

Deliberately simple: incremental, greedy, explainable. A coordinator must be able to understand why a sighting
joined a pack, because they have to correct it.

```
On sighting sync → enqueue cluster-sighting(sighting_id)

1. Load sighting. Skip if status != 'active'.
2. Candidates = active|proposed packs in the same org where
     ST_DWithin(pack.centroid, sighting.location, R)
     AND pack has a linked sighting with occurred_at > now() - W
   R = org.cluster_radius_m (default 300)
   W = org.cluster_window_days (default 90)
3. Score each candidate:
     score = 0.6 * (1 - distance/R)
           + 0.25 * recency_factor(most_recent_linked_sighting)
           + 0.15 * count_similarity(pack.animal_count_estimate, sighting.animal_count_estimate)
4. Best score >= 0.5 → link (sighting_pack.linked_by='auto', confidence=score)
   else → create pack, status='proposed', linked_by='auto', confidence=score
5. Recompute pack centroid (unless centroid_is_manual), animal_count_estimate, notched_ratio_observed.
6. Emit pack.updated / pack.proposed. Write audit events with actor_type='system'.
```

Defaults come from the field reality that Romanian village dog packs hold territory on the scale of a few hundred
metres, and that a pack unseen for a season may have dispersed. Both are org-configurable because a sparse rural
county and a dense city district behave differently.

### 3.3 Design constraints

- **Advisory, never authoritative.** Every auto decision is visible with its confidence and reversible without
  data loss (`FR-042`). `sighting_pack.unlinked_at` preserves the history of a reversed decision.
- **Idempotent.** Re-running for the same sighting must not create a second link or a duplicate pack. Guarded by
  a unique constraint on `(sighting_id, pack_id)` where `unlinked_at IS NULL`.
- **Not on the request path.** Sync must stay under 500 ms (`NFR-002`).
- **Serialised per org** with an advisory lock, so two sightings arriving together cannot each create a pack for
  the same location. This is a real race: a volunteer syncs a week of pins in one batch.

### 3.4 Deliberately not done in Phase 1

Photo-based individual re-identification, movement-corridor inference, and population estimation by
mark-recapture. All need a labelled corpus that only Phase 1 usage can produce. The clustering interface is
isolated behind `PackClusteringStrategy` so a better implementation is a swap, not a rewrite.

## 4. Route optimisation

### 4.1 Problem shape

A capacitated vehicle routing problem with a single vehicle per mission, a depot start/end, a mission time
window and cage capacity as the binding constraint. Typical size: 5–25 stops. Occasionally 60.

Cage capacity matters more than distance: a van with 8 cages cannot usefully visit packs totalling 30 animals in
one run. Optimising purely for distance produces plans the field team quietly ignores, which is worse than no
optimisation at all.

### 4.2 Pipeline

```
POST /v1/missions/{id}/optimise
   ↓ enqueue optimise-mission
1. Build stop set: depot + selected packs (+ clinic stops).
2. OSRM /table/v1/driving  → duration + distance matrix (real road network).
3. VROOM: jobs (with capacity demand = estimated animals), one vehicle with
   capacity + time window + depot, → ordered solution.
4. Persist stop sequence, per-stop ETA, planned_distance_m, planned_duration_s,
   optimisation_engine='vroom', optimisation_version=<version>, optimisation_mode='optimised'.
5. Emit mission.optimised; audit event.
```

Both OSRM and VROOM are self-hosted in one container from a Romania OSM extract (~250 MB PBF). Rationale in
ADR-0011: commercial matrix APIs price per element, a 25×25 matrix is 625 elements, re-optimisation is frequent,
and this would become a top cost line for zero functional gain.

### 4.3 Degraded mode

If OSRM or VROOM is unavailable, the API offers a **nearest-neighbour ordering over great-circle distance** with
`optimisation_mode = 'fallback_straight_line'`. It must be labelled in every UI surface that shows the plan
(`FR-075`). Straight-line ordering in a country with mountains and unpaved roads can be badly wrong; presenting
it as optimised would destroy the trust the product is built on.

### 4.4 Constraints honoured in Phase 1

| Constraint | Handling |
|---|---|
| Cage capacity | VROOM capacity dimension = summed `animal_count_estimate` |
| Mission time window | Vehicle time window; per-job service time (default 20 min/pack, configurable) |
| Depot start/end | Vehicle `home_depot`, overridable per mission |
| Notched-ratio deprioritisation | Packs above threshold get a lower priority weight (`FR-045`) |
| Manual override | Coordinator reorder persists; re-optimisation requires confirmation (`FR-076`) |

Not in Phase 1: multi-vehicle joint optimisation, multi-day planning, driver shift rules, live re-routing.
Multi-vehicle is the most likely first extension — VROOM already supports it, so this is a parameter change plus
UI, tracked as `TNR-098`.

### 4.5 Performance

≤ 25 stops in ≤ 10 s p95 (`NFR-006`). The matrix call dominates. Mitigations: cache the pairwise matrix per
`(rounded coordinate pair, profile)` in Redis with a 30-day TTL — pack centroids barely move, so hit rates are
high across re-optimisations; and cap VROOM's exploration time. Above 60 stops the job reports progress and the
UI stops pretending it is interactive.

## 5. Map rendering

### 5.1 Stack

MapLibre GL JS with self-hosted **PMTiles** served from object storage (ADR-0007). A Romania-only vector basemap
extract is a single ~400 MB PMTiles archive; MapLibre range-requests it directly from R2. No tile server to
operate, no per-request commercial fee (`NFR-053`).

### 5.2 Layers

| Layer | Source | Notes |
|---|---|---|
| Basemap | PMTiles vector | Muted style; data must dominate |
| Packs | GeoJSON from API, clustered | Colour by status, size by estimated count |
| Sightings | GeoJSON, viewport-bounded | Visible when zoomed in past the cluster threshold |
| Mission route | GeoJSON LineString from OSRM geometry | Numbered stop markers |
| Coverage choropleth | Locality polygons + `metric_snapshot` | "No data" visually distinct from "zero coverage" (`FR-119`) |
| Draft pin | Client-only | Draggable, with an accuracy circle |

### 5.3 Offline tiles (`FR-029`, `NFR-005`)

The field client caches a bounded region:

```
1. Coordinator (or volunteer) selects an operating region — county, or a mission corridor buffer.
2. Client computes the tile ranges for zooms 8–14 and range-requests those PMTiles byte ranges.
3. Bytes are stored in Cache Storage, indexed in Dexie with size accounting.
4. Budget default 150 MB, warning at 80%, LRU eviction of whole regions (never partial, which would
   leave visibly broken map areas).
5. Uncached areas render as an explicit hatched "no map data" state, never as blank white — a blank map
   reads as a broken app.
```

Zoom 8–14 is the useful band: 14 is enough to identify a farmstead, and going deeper multiplies size for detail a
volunteer standing there does not need.

### 5.4 Field-mode map

Field mode loads a minimal map: basemap plus the current mission's stops and the draft pin. No clustering
machinery, no choropleth, no chart libraries. This is what keeps field mode inside its 250 KB budget
(`NFR-004`), and it is enforced by the bundle-composition check.

## 6. Privacy in geography

Precise locations are dangerous data. Published stray-dog coordinates enable poisoning and abuse, and yard-dog
sightings can indirectly identify a household.

| Rule | Implementation |
|---|---|
| Precise geometry never leaves the owning org | `funder` responses omit geometry fields and return locality centroids (`FR-031`) |
| No public map | No unauthenticated spatial endpoint exists |
| Aggregation floor for funder views | Locality level; a locality with < 3 packs reports only a count, no centroid |
| Household inference | Owned-dog sightings marked `is_owned` are excluded from funder-visible layers entirely |
| Logs | Coordinates are never logged (`NFR-034`) |

## 7. Testing geospatial code

- **Fixture coordinates** are real Romanian locations (Pitești, Slatina, Curtea de Argeș, and a deliberate remote
  village) held in one fixture module. No random coordinates in tests — reproducibility matters more than variety.
- **Swap detection**: an assertion that every fixture point is inside Romania's bounding box.
- **Distance assertions** use known pairs with a tolerance of ±1 m, so a CRS or units mistake fails loudly.
- **Clustering tests** are table-driven over hand-built scenarios: two pins 50 m apart same week (one pack); two
  pins 5 km apart (two packs); a pin near a pack last seen 200 days ago (new pack); the same pin twice
  (idempotent).
- **Routing tests** use a recorded OSRM/VROOM fixture; the live engine is exercised only in an integration suite
  tagged for the nightly run.
- Every spatial integration test runs against a real `postgis/postgis` container. Mocking PostGIS proves nothing.

## 8. Open questions

> **OQ-GEO-1** — Source and licence for Romanian locality boundaries with SIRUTA codes. Candidates: OSM
> administrative relations, geo-spatial.org datasets. Must be resolved before `TNR-095` (coverage choropleth).

> **OQ-GEO-2** — Per-pack service-time default of 20 minutes is a guess. Instrument actual stop durations from
> mission outcomes and calibrate after the first campaign. Tracked as `TNR-099`.

> **OQ-GEO-3** — Should re-optimisation be automatic when a stop is skipped mid-mission? Field feedback needed;
> automatic re-routing a driver who is already moving may be unwelcome.
