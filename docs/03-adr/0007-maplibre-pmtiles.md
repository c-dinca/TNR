# ADR-0007: MapLibre GL JS with self-hosted PMTiles

- **Status**: Accepted
- **Date**: 2026-08-05
- **Affects**: `apps/web`, tile hosting, `infra/`

## Context

Maps are the primary interface for both personas. Requirements: offline basemap caching for field use
(`FR-029`, `NFR-005`), no per-request commercial fee at Phase 1 volumes (`NFR-053`), and a €150/month total
infrastructure budget (`NFR-050`).

Romania-only coverage is sufficient.

## Options considered

### Option A — Mapbox GL JS + Mapbox tiles

**For:** Excellent tiles, great styling tools, mature SDK.
**Against:** Per-map-load pricing that scales with exactly the usage we want to encourage; terms restrict offline
caching, which is a hard requirement here rather than a nicety; the SDK licence changed to non-open, creating
long-term risk.

### Option B — Google Maps

**For:** Familiar; best road data in some regions.
**Against:** Expensive per load; offline caching effectively prohibited; heavy SDK; terms unfriendly to storing
derived data.

### Option C — Leaflet + raster tiles from a public OSM server

**For:** Simple, small, well known.
**Against:** Public OSM tile servers explicitly prohibit heavy application use; raster tiles are large and cannot
be restyled; no vector features means worse clustering and interaction; running our own raster tile server means
storage and CPU we do not want to own.

### Option D — MapLibre GL JS + self-hosted PMTiles

MapLibre is the open fork of Mapbox GL JS. PMTiles is a single-file archive of vector tiles served over HTTP range
requests, needing no tile server at all.

**For:** No per-request fee; the whole of Romania (zooms 0–14) is one ~400 MB archive in R2, fronted by the
Cloudflare cache; range requests make offline region caching straightforward (`FR-029`); vector tiles restyle
freely and support proper clustering; fully open licensing.
**Against:** We own the tile pipeline, including periodic regeneration; styling requires more work than a hosted
studio; PMTiles has a smaller community than Mapbox's ecosystem; a very large viewport can issue many range
requests.

## Decision

**Option D.** MapLibre GL JS with a self-hosted Romania PMTiles archive on R2 behind Cloudflare.

Zooms 0–14. Zoom 14 identifies a farmstead, which is as precise as a volunteer standing there needs; going deeper
multiplies archive size for no operational gain.

Offline caching stores whole regions with LRU eviction — never partial regions, which would leave visibly broken
map areas and read as a broken app.

## Consequences

**Positive** — effectively zero marginal map cost; offline caching is a first-class capability rather than a
licence violation; consistent styling across app and report maps; no vendor lock-in.

**Negative** — we own tile regeneration (a tracked quarterly task); initial styling effort; OSM attribution must
appear in every map view **and** every report map, which is a legal obligation and easy to forget; the PMTiles
archive is a large build artefact to manage.

**Neutral** — extending beyond Romania means generating another archive, which is a pipeline run rather than a
contract negotiation.

## Revisit when

Coverage is needed outside Romania at a scale where maintaining archives is worse than paying a vendor, or if
range-request volume against R2 becomes a measurable cost.
