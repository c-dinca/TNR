# API design

The machine-readable contract is [`../../contracts/openapi.yaml`](../../contracts/openapi.yaml). It is
normative: TypeScript types for the client are generated from it, and a CI job fails when the implementation and
the spec diverge. This document defines the conventions the spec obeys.

---

## 1. Ground rules

| Rule | Value |
|---|---|
| Style | REST over HTTPS, JSON |
| Base path | `/v1` — additive changes only within a major version |
| Auth | `Authorization: Bearer <access token>` |
| Errors | RFC 9457 `application/problem+json`, always |
| Lists | cursor pagination, `limit` ≤ 200 |
| Mutations | `Idempotency-Key` header accepted on all, required on `/v1/sync` |
| IDs | UUIDv7 in path segments; client-supplied for offline-created resources |
| Casing | `snake_case` in JSON bodies, matching the database, so no mapping layer can drift |
| Time | RFC 3339 with `Z`, microsecond precision preserved |
| Coordinates | GeoJSON-style `[lon, lat]` arrays. **Longitude first**, always |

Longitude-first is stated because it is the single most common source of silent geospatial bugs. Every DTO uses
`{"type":"Point","coordinates":[lon,lat]}`, never a bare pair, never `{lat,lng}`.

## 2. Versioning

`v1` accepts additive change only: new optional request fields, new response fields, new endpoints. Removing a
field, narrowing a type, tightening validation, or changing a default is a **breaking** change requiring `v2`
plus an ADR.

The reason is offline clients: a volunteer's phone may run a build that is three months old and hold a week of
queued mutations. The server must accept them. Concretely:

- The server never rejects an unknown extra field in a request body — it ignores it.
- The client never assumes a response field exists without a guard.
- A client that must be updated learns so via `X-TNR-Min-Client: <semver>` on any response; on receiving a
  version below the minimum it shows an update prompt but **still drains its outbox first** (`NFR-015`).

## 3. Authentication and session

| Method | Path | Notes |
|---|---|---|
| POST | `/v1/auth/register` | Creates user + org + owner membership (`FR-001`) |
| POST | `/v1/auth/login` | Returns access + refresh token |
| POST | `/v1/auth/refresh` | Rotating refresh; reuse revokes the family (`FR-004`) |
| POST | `/v1/auth/logout` | Revokes the presented refresh token |
| POST | `/v1/auth/password-reset/request` | Always `202`, never reveals existence (`FR-005`) |
| POST | `/v1/auth/password-reset/confirm` | Single-use token |
| GET | `/v1/auth/me` | User, memberships, active org, permissions |
| GET/DELETE | `/v1/auth/sessions[/{id}]` | List and revoke own sessions (`FR-019`) |

Access token: JWT, ≤ 15 min, carries `sub`, `org_id`, `role`, `permissions`, `jti`.
Refresh token: opaque, random, hashed at rest, ≤ 90 days, rotating with family revocation on reuse.

Active org is selected by `POST /v1/auth/switch-org` which mints a new access token; the refresh token is
org-independent. Never take `org_id` from a request body (`FR-030`).

## 4. Resource endpoints

Conventional shape, `{org}` implied by the session:

```
GET    /v1/{collection}          list, filtered, cursor-paginated
POST   /v1/{collection}          create
GET    /v1/{collection}/{id}     read
PATCH  /v1/{collection}/{id}     partial update
DELETE /v1/{collection}/{id}     soft delete
```

Collections: `sightings`, `packs`, `animals`, `interventions`, `missions`, `vehicles`, `campaigns`, `grants`,
`members`, `invitations`, `devices` (Phase 2, hidden).

Sub-resources and actions (verbs only where a state transition is not a CRUD operation):

| Method | Path | Purpose |
|---|---|---|
| POST | `/v1/packs/{id}/merge` | Body: `{ source_pack_ids: [] }`. Audited (`FR-043`) |
| POST | `/v1/packs/{id}/split` | Body: `{ sighting_ids: [], new_pack_name }` |
| POST | `/v1/packs/{id}/close` | Body: `{ reason }` from the fixed set (`FR-044`) |
| POST | `/v1/packs/{id}/confirm` | `proposed → active` |
| GET | `/v1/packs/{id}/history` | Audit-derived timeline |
| POST | `/v1/missions/{id}/optimise` | `202` + `job_id` (`FR-073`) |
| POST | `/v1/missions/{id}/status` | Enforced transition (`FR-083`) |
| PATCH | `/v1/missions/{id}/stops/order` | Manual reorder (`FR-076`) |
| POST | `/v1/missions/{id}/stops/{stopId}/outcome` | Offline-capable outcome (`FR-078`) |
| POST | `/v1/missions/{id}/cache-bundle` | Returns everything needed for offline execution (`FR-077`) |
| POST | `/v1/interventions/{id}/correct` | Creates a superseding record (`FR-093`) |
| POST | `/v1/animals/{id}/chip-lookup` | `202`, async enrichment (`FR-054`) |
| GET | `/v1/media/presign` | Short-lived upload URL (`FR-060`) |
| POST | `/v1/media/{id}/finalise` | Server-side hash + processing job |
| POST | `/v1/reports` | Async report generation (`FR-113`) |
| GET | `/v1/reports/{id}` | Status + signed download link |
| POST | `/v1/exports/recs-csv` | Date-ranged CSV (`FR-056`) |
| GET | `/v1/audit/verify` | Chain verification (`FR-105`) |
| GET | `/v1/metrics/campaign/{id}` | Dashboard projection + freshness (`FR-112`) |
| GET | `/v1/jobs/{id}` | Async job status (`NFR-064`) |
| GET | `/healthz`, `/readyz` | Unversioned. Commit SHA in `/healthz` (`NFR-044`) |

Actions are `POST /{resource}/{id}/{action}`. Do not invent RPC endpoints outside a resource, and do not model a
state transition as a `PATCH` on a `status` field where invariants must be checked — `409` on an illegal
transition is far clearer than a validation error on a field.

## 5. Pagination

Opaque cursor, stable ordering, no offsets (offsets break under concurrent inserts, which field sync guarantees).

```
GET /v1/sightings?limit=50&cursor=eyJzZXEiOjEyMzR9&occurred_after=2026-01-01T00:00:00Z
```

```json
{
  "data": [ ... ],
  "page": { "next_cursor": "eyJzZXEiOjEyODR9", "has_more": true, "limit": 50 }
}
```

The cursor encodes the sort key(s) plus the id tiebreaker. Total counts are **not** returned on hot list
endpoints; where a count is genuinely needed (dashboards) it comes from `metric_snapshot`, not `COUNT(*)`.

## 6. Spatial queries

```
GET /v1/packs?bbox=24.8,44.8,25.2,45.1&status=active
GET /v1/sightings?near=25.01,44.93&radius_m=1500&occurred_after=...
```

`bbox` is `minLon,minLat,maxLon,maxLat`. Above the feature cap (2,000) the response switches to clusters and says
so:

```json
{
  "data": [ { "type": "cluster", "coordinates": [25.01, 44.93], "count": 143, "bbox": [...] } ],
  "meta": { "representation": "clustered", "feature_cap": 2000, "zoom_hint": 11 }
}
```

Clients must handle both representations. A client that assumes only features will break at scale, so the
generated types make `data` a discriminated union.

**Funder scoping:** for a `funder` identity, geometry in any response is snapped to locality centroids and
precise geometry fields are omitted entirely — not nulled, omitted — so an accidental render cannot leak
(`FR-031`).

## 7. Errors — RFC 9457

Every non-2xx response is `application/problem+json`:

```json
{
  "type": "https://tnr-os.dev/problems/validation-failed",
  "title": "Validation failed",
  "status": 422,
  "detail": "animal_count_estimate must be >= 1",
  "instance": "/v1/sightings",
  "request_id": "01J8K9...",
  "errors": [
    { "path": "animal_count_estimate", "code": "min", "message": "must be >= 1" }
  ]
}
```

| Status | `type` slug | Used for |
|---|---|---|
| 400 | `malformed-request` | Unparseable body, bad cursor |
| 401 | `unauthenticated` | Missing/expired access token |
| 403 | `forbidden` | Authenticated, lacks permission (`FR-018`) |
| 404 | `not-found` | Absent, or exists in another org (`FR-032`) |
| 409 | `conflict` | Illegal state transition, chip conflict, idempotency-key mismatch |
| 410 | `gone` | Expired invitation, expired signed link |
| 413 | `payload-too-large` | Batch or body over limit |
| 422 | `validation-failed` | Well-formed but invalid |
| 429 | `rate-limited` | With `Retry-After` |
| 503 | `dependency-unavailable` | Postgres/queue down, with `Retry-After` |

Rules: `404` (not `403`) for another org's resource, so existence is never revealed. `request_id` is always
present and always matches the log correlation ID. `detail` is safe to show a user; it must never contain
internal identifiers, SQL, or stack traces.

## 8. Idempotency

Every mutating request accepts `Idempotency-Key` (client UUIDv7). Required on `/v1/sync`.

```
1. Look up (org_id, key). Not found → proceed and store the outcome.
2. Found with the same request hash → return the stored status and body, plus Idempotency-Replayed: true.
3. Found with a different request hash → 409 idempotency-key-reused.
4. Records expire after 24 h.
```

Additionally, resources created offline carry a client-generated `id`. Creating with an existing id **and** an
identical payload is treated as a replay (`200` with the existing resource), not a conflict. Two layers of
protection, because a phone that loses signal mid-request is normal (`FR-026`).

## 9. Sync endpoint

The batch write path for offline clients. Fully specified in
[`05-offline-first-and-sync.md`](05-offline-first-and-sync.md); summarised here.

```http
POST /v1/sync
Idempotency-Key: 01J8K9...
{
  "client_id": "01J8...",
  "client_version": "1.4.2",
  "device_clock_at": "2026-08-05T09:12:33.120Z",
  "mutations": [
    { "op_id": "01J8...", "type": "sighting.create", "occurred_at": "...", "payload": { ... } },
    { "op_id": "01J8...", "type": "mission_stop.outcome", "payload": { ... } }
  ]
}
```

Response is **per-mutation** and never all-or-nothing — one bad record must not block a week of queued work:

```json
{
  "results": [
    { "op_id": "01J8...", "status": "applied", "entity_id": "01J8..." },
    { "op_id": "01J8...", "status": "duplicate", "entity_id": "01J8..." },
    { "op_id": "01J8...", "status": "rejected", "problem": { "type": ".../validation-failed", "status": 422, "detail": "..." } }
  ],
  "server_time": "2026-08-05T09:12:34.001Z",
  "clock_skew_ms": 881
}
```

`duplicate` is a success from the client's perspective: remove from the outbox. `rejected` is terminal — the
client surfaces it for manual attention and does not retry forever. Max 50 mutations, 1 MB per batch. Media never
travels through this endpoint.

## 10. Media upload

```
1. GET /v1/media/presign?content_type=image/jpeg&byte_size=412331&sha256=<hex>
   → { media_id, upload_url, expires_at, headers }
2. PUT the bytes directly to storage (never through the API).
3. POST /v1/media/{media_id}/finalise
   → server HEADs the object, computes SHA-256, compares with the declared hash,
     extracts EXIF, enqueues derivative generation.
4. POST /v1/media/{media_id}/link  { entity_type, entity_id, role }
```

Presign requires the declared hash and size up front, which is what makes step 3's comparison meaningful
(`FR-061`). Reads use `GET /v1/media/{id}/url?variant=web` returning a signed URL expiring in ≤ 15 min
(`FR-065`). Signed URLs are never logged.

## 11. Async operations

Anything that can exceed one second returns `202` with a job handle:

```json
{ "job_id": "01J8...", "status": "queued", "poll_after_ms": 1000, "resource_url": "/v1/jobs/01J8..." }
```

`GET /v1/jobs/{id}` → `queued | running | succeeded | failed`, with `progress`, `result_url` and, on failure, a
problem document. Job records live in Postgres, so status survives a Redis flush (`NFR-047`).

Phase 1 has no websockets. Polling with a server-suggested interval is sufficient and immensely simpler to
operate.

## 12. Rate limits

| Bucket | Limit |
|---|---|
| `POST /v1/auth/login` | 5/min per IP, 10/hour per account, exponential backoff (`FR-008`) |
| `POST /v1/sync` | 60/min per identity |
| `GET /v1/media/presign` | 300/hour per identity |
| Exports & reports | 10/hour per org |
| Chip lookup | 30/hour per org, plus a provider-side global cap |
| Default | 600/min per identity |

`429` carries `Retry-After` and `X-RateLimit-{Limit,Remaining,Reset}`. Field-critical paths (sync, presign) get
deliberately generous limits: throttling a volunteer draining a week's outbox would be worse than the abuse we
are preventing.

## 13. Request/response conventions

**Headers we require or emit**

| Header | Direction | Purpose |
|---|---|---|
| `Idempotency-Key` | in | Replay safety |
| `X-Request-Id` | in/out | Correlation; generated if absent |
| `X-TNR-Client` | in | `web-field/1.4.2`, used for telemetry and min-version checks |
| `X-TNR-Min-Client` | out | Minimum supported client (`NFR-015`) |
| `Idempotency-Replayed` | out | `true` when a stored response was returned |
| `Retry-After` | out | On `429`/`503` |

**Validation** — Zod schemas at the boundary. The schema is the single definition: it validates, it types, and it
generates the OpenAPI fragment. No hand-written DTO interfaces that can drift from validation.

**Field conventions** — `*_at` timestamps, `*_id` references, `*_m`/`*_s` for metres and seconds (units in the
name, never bare `distance` or `duration`), `*_count` for integers, `*_estimate` where the value is inherently
uncertain.

## 14. Permissions surface

Every endpoint declares required permissions in `<module>.permissions.ts` and the guard enforces them from the
membership role. `GET /v1/auth/me` returns the caller's effective permission list so the UI can hide what it
cannot do — while the server still enforces independently. Full matrix in
[`06-auth-and-tenancy.md`](06-auth-and-tenancy.md).

## 15. What the API deliberately does not do

- **No PATCH on `intervention` core fields.** Append-only; use `/correct` (`FR-093`).
- **No `DELETE` on `audit_event`.** No path exists at any layer (`FR-103`).
- **No bulk unbounded export via a GET.** Exports are async, audited, rate-limited jobs (`FR-104`).
- **No `org_id` in any request body.** Session-derived only (`FR-030`).
- **No public unauthenticated read of pack or sighting data.** Ever. Publishing stray locations enables poisoning.
- **No nested writes.** One request creates one resource; batch writes go through `/v1/sync`.
