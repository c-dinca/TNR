# ADR-0014: Hash-chained audit log for donor-grade evidence

- **Status**: Accepted
- **Date**: 2026-08-05
- **Affects**: every mutating path, reporting, evidence packs

## Context

The payer is an international foundation deciding whether to release six figures based on claimed sterilisation
counts (`04-business-model.md` §3). Today that claim rests on a folder of photos and trust. Our differentiator is
making it verifiable (`FR-100`–`FR-106`).

The threat is not only an external attacker. It includes a customer org's insider inflating numbers, and it
includes us — a foundation has no reason to trust a vendor's unverifiable assertion about its own database.

## Options considered

### Option A — Ordinary audit table

**For:** Simple, cheap, standard.
**Against:** Anyone with database access can rewrite it, including us. To a sceptical auditor it proves nothing
beyond what the main tables already claim.

### Option B — Append-only table with database-level restrictions

**For:** Better; a compromised application cannot rewrite history.
**Against:** Still fully rewritable by anyone with the migration role. The guarantee remains "trust the operator".

### Option C — Public blockchain anchoring

**For:** Maximum external verifiability.
**Against:** Transaction cost and latency; operational complexity wildly out of proportion; the credibility cost of
saying "blockchain" to a conservative foundation is real; and anchoring only proves a hash existed at a time, which
a chain plus a published head hash already achieves for our purposes.

### Option D — Per-org hash chain in Postgres, head hash published in every report

Each audit event stores the hash of the previous event's canonical form. Reports and evidence packs carry the head
hash and sequence range at generation time.

**For:** Modifying any past event invalidates every subsequent hash; to forge convincingly, one would have to
rewrite the whole chain *and* every previously issued report, including the copies the funder already holds.
Verification uses `sha256sum` and a short script — no vendor software required (`FR-118`). Cost is one hash
computation per mutation.
**Against:** Chain appends serialise per org; the canonical hash form becomes a published contract that cannot
change casually; a bug that breaks the chain is an integrity incident requiring disclosure.

## Decision

**Option D.** Per-org hash chain, specified in
[`../02-architecture/08-audit-and-donor-reporting.md`](../02-architecture/08-audit-and-donor-reporting.md) §2.

Reinforced by two additional layers: the application database role has no `UPDATE`/`DELETE` on `audit_event`, and
the audit event commits in the same transaction as the change it describes (`FR-102`) so no unlogged mutation is
possible.

Third-party verifiability is the point. Every evidence pack ships a `VERIFY.md`, and **that procedure runs in CI** —
if our own published instructions do not work, the guarantee is theatre.

## Consequences

**Positive** — a defensible, independently checkable evidence claim, which is the commercial differentiator;
tamper detection with a precise `first_broken_seq`; strong protection against insider number-inflation.

**Negative** — chain appends serialise per org via a row lock, which is a measured write-throughput ceiling
(acceptable: tens of events per minute, re-measured in the load test); the canonical form is frozen and changing it
requires a `chain_version` bump plus an ADR, because published instructions depend on it; a chain-breaking bug
becomes a disclosure event rather than a quiet fix.

**Neutral** — `actor_type` (`user | system | device`) is in the hash input from the first event, so Phase 2 devices
need no chain change (ADR and `12-phase-2-iot-seams.md` §5.3). Getting this right at the start is why it costs
nothing later.

## Revisit when

Per-org append contention appears in load testing, or a customer requires external timestamping (an RFC 3161
timestamp authority over the head hash would be the natural addition, and is compatible with this design).
