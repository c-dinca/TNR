# Offline-first architecture and sync protocol

This is the most important document for the field client. If a change here is wrong, volunteers lose data, and a
volunteer who loses data once stops using the product.

**Premise:** the field client is the system of record until it syncs. The network is an optimisation, not a
dependency.

---

## 1. Requirements recap

`FR-024`–`FR-027`, `FR-034`, `FR-035`, `NFR-010`–`NFR-018`. In plain terms:

1. Capture works with the radio off.
2. Nothing is lost to an app kill, a reboot, or a dead battery.
3. Replay never duplicates.
4. The user always knows what has and has not been sent.
5. A 90-day-old client with a week of queued work can still sync.

## 2. Client storage

| Store | Technology | Contents |
|---|---|---|
| Records | IndexedDB via Dexie | Local copies of sightings, missions, stops, animals, interventions |
| Outbox | IndexedDB | Pending mutations with idempotency keys and attempt metadata |
| Media queue | IndexedDB (metadata) + Blob storage | Downscaled images awaiting upload |
| Tiles | Cache Storage | PMTiles byte ranges, size-accounted in Dexie |
| App shell | Cache Storage via service worker | Precached build assets |
| Session | IndexedDB (not `localStorage`) | Refresh token, active org, cached permissions |

Why Dexie over raw IndexedDB: transactions, schema versioning and a query API that agents can read. Why
IndexedDB over `localStorage`: `localStorage` is synchronous, size-capped at ~5 MB, and cannot hold blobs —
unusable for a photo queue.

Session material lives in IndexedDB rather than `localStorage` to reduce XSS exposure surface, alongside a strict
CSP (`NFR-038`).

## 3. The outbox

### 3.1 Record shape

```ts
type OutboxEntry = {
  op_id: string;              // UUIDv7, the idempotency unit
  type: MutationType;         // 'sighting.create' | 'mission_stop.outcome' | ...
  entity_id: string;          // client-generated UUIDv7 of the target record
  payload: unknown;           // validated against the shared schema at enqueue time
  occurred_at: string;        // client-observed event time
  enqueued_at: string;        // device clock at enqueue
  attempts: number;
  next_attempt_at: string;
  last_error?: { code: string; detail: string; retryable: boolean };
  status: 'pending' | 'in_flight' | 'failed' | 'rejected';
};
```

### 3.2 Invariants

1. **Enqueue and local apply are one IndexedDB transaction.** The UI must never show a record that has no outbox
   entry, and vice versa. A crash between the two is the classic source of ghost records.
2. **`op_id` is generated once, at enqueue.** Never regenerated on retry — that is what makes replay idempotent.
3. **Ordering is preserved per entity.** Mutations for the same `entity_id` are sent in enqueue order; a mutation
   whose predecessor failed is held, not skipped. A stop outcome must not arrive before its mission is known.
4. **Payloads are validated at enqueue**, against the same shared schema the server uses. Fail fast on the device
   rather than accumulating garbage that gets rejected a week later in a village.
5. **A `rejected` entry leaves the queue and enters a visible error list.** No infinite retry of something the
   server will never accept.

### 3.3 Retry policy

Exponential backoff with jitter: 5 s, 15 s, 1 min, 5 min, 30 min, 2 h, capped at 6 h (`NFR-014`).
Triggers for an immediate drain attempt: `online` event, app foreground, manual "sync now", successful auth
refresh.

Classification:

| Server response | Client action |
|---|---|
| `applied` / `duplicate` | Remove from outbox; mark the local record synced |
| `rejected` (4xx validation, business rule) | Terminal. Move to the error list with the problem `detail` |
| `409 conflict` | Terminal for that mutation; surface with a resolution hint |
| `401` | Refresh the token, retry once; if refresh fails, keep queued and prompt for re-login **without discarding anything** |
| `429` / `503` | Retry after `Retry-After` |
| Network error / timeout | Retry with backoff |

## 4. Sync protocol

### 4.1 Request

`POST /v1/sync` with up to 50 mutations, 1 MB max, single `Idempotency-Key` for the batch plus per-mutation
`op_id`s.

```json
{
  "client_id": "01J8...",
  "client_version": "1.4.2",
  "device_clock_at": "2026-08-05T09:12:33.120Z",
  "last_pull_cursor": "eyJzZXEiOjk5MDF9",
  "mutations": [
    {
      "op_id": "01J8...",
      "type": "sighting.create",
      "entity_id": "01J8...",
      "occurred_at": "2026-08-05T07:41:02.000Z",
      "payload": {
        "location": { "type": "Point", "coordinates": [24.8712, 44.8563] },
        "location_accuracy_m": 12,
        "animal_count_estimate": 4,
        "notched_count_observed": 1,
        "health_note": "one limping"
      }
    }
  ]
}
```

### 4.2 Server processing

```
1. Authenticate; resolve org from session (never from the body).
2. Batch-level idempotency check: same key + same hash → replay the stored response verbatim.
3. For each mutation, IN ORDER, IN ITS OWN TRANSACTION:
   a. Validate against the schema for `type`.
   b. Check per-op idempotency: op_id seen → 'duplicate'; entity_id exists with identical payload → 'duplicate'.
   c. Apply the domain operation (services, invariants, authorisation).
   d. Write the audit event in the same transaction.
   e. Commit. Record the result.
4. Enqueue derivations (clustering, media processing, metric refresh) AFTER commit.
5. Compute clock skew = server_time - device_clock_at; persist on the created records.
6. Store the batch response for idempotent replay (24 h).
7. Return per-mutation results with server_time and clock_skew_ms.
```

**Per-mutation transactions, not one batch transaction.** One malformed record from an old client version must not
block 49 valid ones. Partial success is the correct semantic for this domain, and the response shape reflects it.

### 4.3 Response

```json
{
  "results": [
    { "op_id": "01J8...A", "status": "applied", "entity_id": "01J8...", "server_created_at": "..." },
    { "op_id": "01J8...B", "status": "duplicate", "entity_id": "01J8..." },
    { "op_id": "01J8...C", "status": "rejected",
      "problem": { "type": "https://tnr-os.dev/problems/validation-failed", "status": 422,
                   "detail": "occurred_at is more than 24h in the future" } }
  ],
  "server_time": "2026-08-05T09:12:34.001Z",
  "clock_skew_ms": 881,
  "pull_cursor": "eyJzZXEiOjk5NDJ9"
}
```

## 5. Pull (server → client)

Field clients need very little server data: their assigned missions, the packs on those missions, and animals
relevant to their work. They do not mirror the org.

```
GET /v1/sync/pull?cursor=<opaque>&scope=assigned
→ { changes: [ { entity_type, entity_id, op: 'upsert'|'delete', data, seq } ], next_cursor, has_more }
```

Cursor is the per-org change sequence. `scope=assigned` returns only the caller's assigned missions and their
dependencies — a bounded set, deliberately, so a phone with 4 GB of RAM is never asked to hold an org's history.

Console mode does not use pull; it queries normally with TanStack Query, because a coordinator on a laptop has
connectivity.

## 6. Conflict resolution

The domain was shaped to make conflicts rare rather than to solve them cleverly.

| Entity | Concurrency model | Rationale |
|---|---|---|
| `sighting` | Append-only. No conflict possible | An observation is a fact about a moment; two observations are two facts |
| `intervention` | Append-only; corrections supersede | Medical records must never be silently overwritten |
| `mission_stop.outcome` | Last-write-wins **by `occurred_at`**, with the loser retained in the audit log | Only one team is at a stop; a later field observation is the better one |
| `pack` curation | Server-authoritative, optimistic `version` check → `409` | Coordinators are online; a real disagreement should be shown, not merged |
| `animal` attributes | Field-level last-write-wins by `occurred_at`, except derived status | Different people legitimately fill different fields |
| `animal.sterilisation_status` | Never client-set; derived from interventions | Prevents a field guess overwriting a surgical fact |

Explicitly rejected: CRDTs and operational transforms (ADR-0006). Sightings are not collaboratively edited
documents; the cost of a CRDT runtime plus its debugging surface buys nothing here.

**Clock handling** (`NFR-018`): the device clock is untrusted. `occurred_at` is stored as reported, along with
`clock_skew_ms`. Ordering, sequencing and the audit chain use the server clock exclusively. Where
`occurred_at` is used as a conflict tiebreaker, skew is compensated first (`occurred_at - clock_skew_ms`), and if
skew exceeds 10 minutes the record is flagged for coordinator review rather than trusted.

## 7. Media queue

Media is separate from the outbox and must never block it (`FR-022`).

```
1. Capture → downscale on-device to ≤ 1600 px / ≤ 500 KB (`FR-023`), preserving EXIF capture time + GPS.
2. Compute SHA-256 on the device. Store the blob + metadata; link it to the parent entity_id locally.
3. Media uploader (independent of outbox drain, throttled to 1 concurrent on a metered connection):
   a. GET /v1/media/presign (declared hash + size)
   b. PUT bytes directly to object storage
   c. POST /v1/media/{id}/finalise
   d. POST /v1/media/{id}/link
4. On success, delete the local blob but keep the metadata row so the UI can show the photo from the network.
5. On failure, retry with the same backoff; surface per-photo status.
```

Ordering: the parent record syncs first when possible, but a photo may legitimately arrive before its parent has
been accepted — the link step retries until the parent exists, with a 7-day give-up window.

On a metered connection the uploader defaults to Wi-Fi-only for originals (a volunteer's data allowance is real
money to them), with a clear per-item "send now" override.

## 8. Service worker strategy

| Asset class | Strategy |
|---|---|
| App shell (JS/CSS/HTML) | Precache, cache-first, versioned by build hash |
| Fonts, icons | Cache-first, long TTL |
| Map tiles (PMTiles ranges) | Cache-first, explicit region caching, LRU by region |
| `GET /v1/**` | Network-first with a cache fallback, only for whitelisted read endpoints |
| `POST /v1/**` | **Never intercepted.** Writes go through the outbox, not through service-worker replay |

Background Sync API is used opportunistically to trigger a drain when the OS allows, but it is never relied upon:
support is uneven and iOS support is absent. The primary triggers stay in-app (`online` event, foreground,
manual).

Update flow: a new service worker activates on next launch, never mid-session, and **never** while the outbox is
non-empty. A schema migration in Dexie runs before any UI renders and must be tested against a populated
database — a failed client migration with pending data is data loss.

## 9. UI contract for sync state

Non-negotiable, because trust is the whole point (`FR-027`, `NFR-064`):

| State | Display |
|---|---|
| Pending | Count badge, "will send when online" |
| Syncing | Progress "3 of 12" |
| Failed (retryable) | Amber, next attempt time, "retry now" |
| Rejected (terminal) | Red, the human-readable reason, the record kept and viewable |
| All synced | Explicit "everything sent" plus the last-sync time |
| Offline | Persistent, calm indicator — never an error, this is normal |

Rules: no indefinite spinner. Never say "saved" if it is only queued — say "saved on this phone". Never
silently drop anything. `deleteDatabase()` is unreachable from the UI while the outbox is non-empty (`FR-006`).

## 10. Testing offline behaviour

| Scenario | Test level |
|---|---|
| Enqueue + local apply atomicity | Unit, with a forced transaction abort |
| Duplicate send of the same `op_id` | Integration, expects `duplicate` and exactly one row |
| Kill the process mid-drain | e2e, Playwright with a forced context close |
| Reject one of 50 mutations | Integration, expects 49 applied |
| Dexie schema migration with 500 pending entries | Unit |
| Clock skew of +2 h and −3 days | Integration, checks ordering is unaffected |
| 7 days of accumulated work, 300 mutations, 200 photos | e2e soak, checks batching and memory |
| Auth expiry mid-drain | Integration, expects refresh then resume with no loss |
| Storage quota exceeded | Unit, expects a graceful warning, not a crash |

The 7-day soak is the single most valuable test in the suite: it is the scenario that breaks naive
implementations and the exact scenario a real volunteer produces after a rural weekend.

## 11. Open questions

> **OQ-SYNC-1** — Should `mission_stop.outcome` allow multi-user concurrent editing at a stop with two teams? Not
> now; needs field evidence that it happens.

> **OQ-SYNC-2** — Should the client hold a bounded pack cache for its whole county to help place pins in areas it
> has never opened? Cost is storage plus pull volume. Revisit after measuring real device storage headroom.
