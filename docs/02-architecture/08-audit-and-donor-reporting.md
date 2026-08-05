# Audit trail and donor reporting

Requirements: `FR-100`–`FR-106`, `FR-110`–`FR-119`, `NFR-009`, `NFR-037`.

This is the half of the product that gets paid for. Field features win adoption; this wins renewal.

---

## 1. Why a hash chain

An NGO asking a foundation for €200,000 must prove that a claimed 3,000 sterilisations happened. Today that proof
is a folder of photos and an assertion. A plain database audit table is barely better: whoever runs the database
can rewrite it.

A hash-chained log gives a materially stronger claim: **any modification to a past record invalidates every
subsequent hash**, and the current head hash is printed in reports the foundation already holds. To forge history
convincingly you would have to rewrite every subsequent event *and* every previously issued report, including the
copies in the funder's own archive.

This is not blockchain, and no distributed ledger is involved. It is a per-org Merkle-style chain in Postgres,
verifiable with `sha256sum` and a short script. Cheap, boring, and enough.

## 2. Audit event structure

Table and hashing function are specified in [`02-data-model.md`](02-data-model.md) §3.12. The essentials:

```
audit_event(org_id, seq, occurred_at, actor_user_id, actor_type, action,
            entity_type, entity_id, diff, request_id, ip_hash, prev_hash, hash, chain_version)

hash = SHA256( chain_version || org_id || seq || occurred_at || actor_type ||
               coalesce(actor_user_id,'-') || action || entity_type || entity_id ||
               canonical_json(diff) || coalesce(prev_hash,'GENESIS') )
```

`canonical_json`: keys sorted lexicographically, no insignificant whitespace, UTF-8, numbers in shortest
round-trip form. **This function is a published verification contract.** Changing it requires a `chain_version`
bump and an ADR, because third parties will have scripts that depend on it.

### 2.1 Append procedure

```sql
BEGIN;
  SELECT audit_head_hash, audit_head_seq FROM org WHERE id = $org FOR UPDATE;  -- serialises the chain
  -- ... the domain change ...
  INSERT INTO audit_event (..., seq = head_seq + 1, prev_hash = head_hash, hash = <computed>);
  UPDATE org SET audit_head_hash = <computed>, audit_head_seq = head_seq + 1 WHERE id = $org;
COMMIT;
```

Consequences, all intentional:

- The audit event and its change commit together or not at all (`FR-102`). No unlogged mutation is possible.
- Chain appends serialise per org. A busy org writes tens of events per minute; this is not a bottleneck, and the
  row lock is held for the duration of one small transaction.
- A sync batch of 50 mutations takes the org lock 50 times sequentially. Measured cost is a few milliseconds each,
  well inside the 500 ms sync budget (`NFR-002`), and it is re-measured in the load test.

### 2.2 What is audited

| Category | Actions |
|---|---|
| Identity | `user.registered`, `session.created`, `session.revoked`, `login.failed`, `token.reuse_detected`, `password.changed`, `permission.denied` |
| Org | `org.created`, `org.updated`, `membership.created/updated/revoked`, `invitation.created/accepted/revoked` |
| Field data | `sighting.created`, `sighting.status_changed`, `pack.proposed/confirmed/merged/split/closed/renamed`, `animal.created/updated`, `animal_pack.changed` |
| Clinical | `intervention.created`, `intervention.corrected`, `intervention.superseded` |
| Operations | `mission.created/updated/status_changed/optimised`, `stop.outcome_recorded`, `vehicle.*` |
| Evidence | `media.finalised`, `media.quarantined`, `media.linked/unlinked`, `media.gc_deleted` |
| Reporting | `report.generated`, `evidence_pack.built`, `export.performed` (with row counts, `FR-104`) |
| Compliance | `dsr.export_performed`, `dsr.erasure_performed`, `retention.sweep_executed` |
| System | `clustering.decided` (`actor_type='system'`), `job.failed_terminally` |

`diff` holds `{ before, after }` with changed fields only. Redacted from diffs: password hashes, tokens, signed
URLs, and free-text medical notes (`NFR-034`) — the note's presence and length are recorded, not its content, so
the chain still detects tampering without turning the audit log into a shadow copy of sensitive text.

### 2.3 Immutability enforcement

Three layers:

1. No repository, service or endpoint exposes update or delete for `audit_event` (`FR-103`).
2. The application's database role has `INSERT, SELECT` only on that table — no `UPDATE`, no `DELETE`. Migrations
   run as a separate, more privileged role.
3. Verification (`FR-105`) can detect tampering after the fact even if 1 and 2 were bypassed.

## 3. Chain verification

`GET /v1/audit/verify?from_seq=&to_seq=` recomputes hashes over a range and reports the first broken link:

```json
{
  "org_id": "01J8...",
  "range": { "from_seq": 1, "to_seq": 48210 },
  "verified": true,
  "head_hash": "9f2c...",
  "checked_at": "2026-08-05T10:00:00Z",
  "first_broken_seq": null
}
```

A nightly job verifies the previous day's segment per org and alerts on any failure. Full-chain verification is
available on demand and is expected to be used before a major grant submission.

**Independent verification** is the point. Every evidence pack contains a `VERIFY.md` explaining the canonical
form and the hash computation, plus the chain excerpt, so a foundation's auditor can verify with standard tools
and no TNR-OS software (`FR-118`). A verification claim that only our code can check is worth very little.

## 4. Metrics and projections

### 4.1 Why projections

`FR-112` requires a dashboard in ≤ 2 s at p95 with 50,000 interventions (`NFR-007`). Live `GROUP BY` over the
intervention table with joins to packs and localities does not hold that under a shared Postgres. So aggregates are
precomputed into `metric_snapshot`, refreshed at most 5 minutes behind, and the UI **always shows the freshness
timestamp**. Honest staleness beats a spinner or a lie.

### 4.2 Metric catalogue

| `metric_key` | Dimensions | Definition |
|---|---|---|
| `interventions.count` | type, day, campaign, locality | Count from `intervention_effective` |
| `interventions.cost_total` | currency, campaign, month | Sum of `cost_amount` |
| `interventions.cost_per_unit` | type, campaign | cost_total / count |
| `sterilisations.count` | campaign, locality, month | `type = 'sterilisation'` |
| `animals.confirmed_sterilised` | locality | Distinct animals with terminal status |
| `packs.identified` | locality, status | Count of packs |
| `packs.covered` | locality | Packs with ≥ 1 sterilisation intervention in the period |
| `coverage.estimate` | locality | confirmed_sterilised / `locality.dog_population_estimate` |
| `sightings.count` | day, user, locality | Field activity |
| `missions.distance_planned_m` / `_actual_m` | campaign, month | Fuel-saving evidence |
| `missions.completion_rate` | campaign | completed stops / planned stops |
| `volunteers.active` | month | Distinct users creating ≥ 1 sighting |
| `sync.failure_rate` | day | Health, internal only |

**Every reporting query reads `intervention_effective`**, never the base table — superseded and deleted rows must
never inflate a donor number. This is the single most consequential query rule in the codebase.

### 4.3 Refresh

An incremental job runs every 5 minutes over rows changed since its watermark; a full nightly recompute
self-heals drift. `metric_snapshot` is fully rebuildable from source, and a rebuild command exists and is
tested — a projection that cannot be rebuilt is unversioned state, not a projection.

Coverage deserves care: `coverage.estimate` divides by an external population estimate whose provenance is
uncertain (OQ-DM-3). Every surface that displays coverage must show its denominator source and label it an
estimate. Publishing a confident coverage percentage built on a guessed denominator would be the fastest way to
lose credibility with a funder who checks.

## 5. Donor reports

### 5.1 Contents (`FR-114`)

1. **Cover** — org, campaign, period, generation timestamp, data snapshot time, audit head hash.
2. **Executive summary** — interventions by type, animals sterilised, packs covered, localities reached.
3. **Time series** — interventions per week over the period.
4. **Geography** — a locality-level map. **Never precise pack locations** (`FR-031`).
5. **Efficiency** — cost per intervention where costs exist; planned vs. actual distance.
6. **Coverage** — estimated change over the period, with the denominator source stated.
7. **Evidence sample** — a deterministic pseudo-random sample of interventions with photos, hashes and capture
   times.
8. **Verification** — head hash, seq range, and how to verify independently.
9. **Methodology** — how each number is derived, and what it does not mean.

Section 9 exists because a programme officer must defend these numbers to a board. "Coverage" computed against an
uncertain denominator, stated plainly, is credible; the same number presented as fact is not.

### 5.2 Generation

```
POST /v1/reports { campaign_id, kind, period_start, period_end, locale }
  → 202 { job_id }
worker generate-report:
  1. Freeze snapshot_at = now(); read the org's audit head hash.
  2. Query all metrics as of snapshot_at (no live reads after this point).
  3. Render an HTML template (locale-aware) → PDF.
  4. Store the PDF as media; create the report row with params, snapshot_at, head hash.
  5. Audit event report.generated. Email a signed link if requested.
```

**Reproducibility** (`FR-115`): the same parameters and snapshot must produce byte-identical output. That requires
eliminating every source of nondeterminism — no `now()` in templates, fixed font subsetting, a fixed PDF
producer/creation date derived from `snapshot_at`, deterministic sampling seeded by `report_id`, and stable sort
orders on every query. A CI test generates the same report twice and diffs the bytes.

Determinism matters because a funder who regenerates a report and gets a different file has no reason to trust
either copy.

Sizing: ≤ 60 s p95 for a 12-month, 5,000-intervention campaign (`NFR-009`). Locales: `ro`, `en`, `de`
(`FR-113`).

### 5.3 Rendering choice

Headless Chromium (Playwright) rendering an HTML template. Rationale: the same components and i18n catalogue as the
web app, real typography, maps as pre-rendered raster images, and no second layout system to maintain. The cost is
a ~300 MB image in the worker, accepted because the alternative (a programmatic PDF library) means maintaining a
parallel layout implementation that will visually drift from the product.

## 6. Evidence packs

`FR-117`, `FR-118`. A streamed ZIP:

```
evidence-pack-{campaign}-{period}.zip
├── REPORT.pdf                  the donor report
├── interventions.csv           one row per effective intervention
├── media/manifest.csv          media_id, entity, role, sha256, captured_at, uploader, storage_path
├── media/…                     included photos (web variant), or a manifest-only pack for large campaigns
├── audit/chain-excerpt.jsonl   the audit events covering the period
├── audit/head.txt              head hash + seq at snapshot time
└── VERIFY.md                   independent verification instructions
```

`VERIFY.md` specifies the canonical form, gives a reference `sha256sum` procedure for the media manifest, and
shows how to recompute the chain with a short standalone script. The pack's own hash is written to the audit log
(`FR-118`), so the archive a funder holds can be proven to be the archive we produced.

Archives stream to object storage rather than buffering in memory (`NFR-052`), so a 5,000-photo pack does not
require 5 GB of worker RAM.

## 7. Billing metering

Business tiers key on volume (`04-business-model.md` §2), so per-org, per-period counts must be cheap and
trustworthy:

| Meter | Source |
|---|---|
| Interventions per year | `metric_snapshot` `interventions.count`, rolled to the subscription year |
| Vehicles coordinated | Distinct vehicles with ≥ 1 mission in the period |
| Active volunteers | Distinct users creating ≥ 1 sighting in the month |

Overage is **surfaced, never enforced** in Phase 1. Blocking a volunteer mid-campaign because a counter tripped
would damage the mission the product exists to serve, and would be remembered longer than any invoice.

## 8. Testing

| Property | Test |
|---|---|
| Chain integrity | Insert 1,000 events, verify; tamper with one row directly in SQL, expect the exact `first_broken_seq` |
| Transactional coupling | Force the audit insert to fail, assert the domain change rolled back |
| Immutability | Assert the app DB role lacks `UPDATE`/`DELETE` on `audit_event` |
| Superseded exclusion | Correct an intervention, assert every metric counts it once |
| Report determinism | Generate twice, diff bytes |
| Projection rebuild | Truncate `metric_snapshot`, rebuild, compare against live aggregates |
| Evidence pack | Build a pack, verify every manifest hash against storage, run the `VERIFY.md` procedure in CI |
| Funder scoping | Assert no precise geometry appears anywhere in a funder-visible report |

The `VERIFY.md` procedure runs in CI. If our own published instructions do not work, the guarantee is theatre.
