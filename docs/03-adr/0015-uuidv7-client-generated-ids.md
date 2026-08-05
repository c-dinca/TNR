# ADR-0015: Client-generated UUIDv7 primary keys

- **Status**: Accepted
- **Date**: 2026-08-05
- **Affects**: schema, sync protocol, client

## Context

Offline-created records need a final identity **before** they reach the server (`FR-024`). A volunteer captures a
sighting, attaches photos, and links them — all with the radio off. Those links must survive sync without a
rewriting step.

Sync replay must also be idempotent (`FR-026`): the same record submitted twice must not create two rows.

## Options considered

### Option A — Server-generated `bigserial`

**For:** Compact, fast, naturally ordered, great index locality.
**Against:** The client cannot know the id until sync. Local relationships need temporary ids and a post-sync
rewriting pass across records, media links and the outbox — a well-known source of subtle offline bugs. Sequential
ids also leak volume information across tenants.

### Option B — Server-generated UUIDv4

**For:** No enumeration; no rewriting if the server allocates on first contact.
**Against:** Still requires a round trip before identity exists, so it does not solve the offline case. And UUIDv4's
randomness causes poor B-tree locality and index bloat at the volumes we expect on `sighting`.

### Option C — Client-generated UUIDv4

**For:** Identity is available offline immediately.
**Against:** Index locality problem remains; random inserts fragment the index on the highest-volume table.

### Option D — Client-generated UUIDv7

Time-ordered UUIDs: a millisecond timestamp prefix plus randomness.

**For:** Identity offline immediately, so no rewriting pass; time-ordered, so B-tree inserts stay largely
sequential and locality approaches a serial key; globally unique, so a duplicate submission collides with itself
and becomes an idempotency signal rather than a duplicate row; the creation time is embedded, which is useful for
debugging and for cursor construction.
**Against:** 16 bytes rather than 8; the embedded timestamp leaks approximate creation time (harmless here — it is
already in `created_at`); a device with a badly wrong clock produces out-of-order ids; UUIDv7 library support is
newer than v4's.

## Decision

**Option D.** UUIDv7 for all primary keys, generated **client-side** for offline-created entities (`sighting`,
`animal`, `intervention`, media) and server-side for server-only entities.

Duplicate-id submission with an identical payload is treated as a replay (`200` with the existing resource), which
is the second of the two idempotency layers described in
[`../02-architecture/03-api-design.md`](../02-architecture/03-api-design.md) §8.

Client clock skew is recorded but never trusted for ordering (`NFR-018`); server `created_at` and the audit `seq`
provide authoritative order, so an out-of-order id is a cosmetic anomaly rather than a correctness problem.

## Consequences

**Positive** — no post-sync id rewriting, eliminating an entire category of offline bug; natural idempotency on
replay; good index locality despite being a UUID; local relationships (sighting ↔ media) are valid the moment they
are created.

**Negative** — 16-byte keys inflate indexes relative to `bigserial`; a malicious client could craft ids, so
per-org uniqueness and authorisation must be enforced server-side regardless; ids from a device with a wrong clock
sort oddly.

**Neutral** — cursors are built from `(created_at, id)` rather than a single sequence, which is a small amount of
extra pagination code.

## Revisit when

Index size on `sighting` becomes a measured problem — the fix would be a `bigint` surrogate for internal joins
while keeping the UUID as the external identity, not a change to client-side generation.
