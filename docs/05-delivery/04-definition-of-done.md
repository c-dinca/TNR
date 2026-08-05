# Definition of done

An item is `done` only when **every applicable box** is checked. "Applicable" is judged honestly — if a box does
not apply, say why in the PR rather than silently skipping it.

---

## Universal

- [ ] Acceptance criteria in the backlog item are all demonstrably true
- [ ] The requirement IDs (`FR-###`/`NFR-###`) the item claims are each covered by a test
- [ ] `pnpm lint`, `pnpm typecheck`, `pnpm test`, `pnpm test:int` pass locally
- [ ] The full CI gate is green
- [ ] No new `any`, no non-null assertion outside tests, no empty `catch`
- [ ] No `TODO` without an item ID
- [ ] No formatting churn in files the change did not otherwise touch
- [ ] New dependencies justified in the PR description (or none added)
- [ ] Backlog item status updated

## Data and schema

- [ ] Migration is hand-written, forward-only, correctly numbered
- [ ] Migration applies cleanly from an empty database (replay test)
- [ ] Migration is backward-compatible with the currently deployed application (`NFR-026`)
- [ ] Expand/contract respected — nothing destructive in the same release that stopped using it
- [ ] Drizzle schema matches; the drift check passes
- [ ] Every new tenant table has non-nullable `org_id` and `deleted_at`
- [ ] New timestamps are `timestamptz` and named `*_at`
- [ ] New locations are `geography(Point, 4326)`
- [ ] Indexes added are justified by a real query, and no more

## API

- [ ] `contracts/openapi.yaml` updated; generated types compile; drift check passes
- [ ] Change is additive within `v1`, or an ADR justifies a breaking change
- [ ] Errors are RFC 9457 problem documents with a `request_id`
- [ ] Mutating endpoints accept `Idempotency-Key`
- [ ] Lists are cursor-paginated with a capped `limit`
- [ ] `org_id` derived from the session, never from client input
- [ ] Permissions declared in `<module>.permissions.ts` **and** re-checked in the service layer
- [ ] The new route is covered by the adversarial tenancy suite

## Domain integrity

- [ ] Every mutation writes an audit event **in the same transaction**
- [ ] Interventions remain append-only; corrections supersede
- [ ] Reporting reads `intervention_effective`, never the base table
- [ ] Derived values (sterilisation status, coverage) are computed, not client-settable
- [ ] Unknown values display as unknown, never as zero
- [ ] Soft delete used for domain records; hard delete only on the GDPR path

## Offline (if any field path is touched)

- [ ] The flow completes with the radio off
- [ ] Records are created with client-generated UUIDv7
- [ ] Mutations enqueue with an `op_id`; enqueue and local apply are one transaction
- [ ] Replay is idempotent — verified by a forced double-send test
- [ ] Media never blocks the parent record
- [ ] Sync state is displayed honestly: pending / syncing / failed with reason
- [ ] Nothing can clear local data while the outbox is non-empty
- [ ] Tested with the process killed mid-operation

## Frontend

- [ ] Bundle budgets met: field ≤ 250 KB gz, console ≤ 600 KB gz
- [ ] Field mode imports no chart, grid or PDF library
- [ ] All user-facing strings are i18n keys; `ro` and `en` catalogues complete
- [ ] Touch targets ≥ 48 px on field surfaces
- [ ] axe reports no violations
- [ ] Empty, loading, error and offline states all designed and implemented
- [ ] No indefinite spinner; no "saved" for something only queued

## Security and privacy

- [ ] No PII, coordinates, tokens, signed URLs or medical notes reachable by a logger
- [ ] Secrets from the environment, schema-validated at boot
- [ ] New personal data justified, minimised, and covered by retention
- [ ] Funder-visible surfaces omit precise geometry — omitted, not nulled
- [ ] Any new external call is EU-region, rate-limited, timed out, and has a documented degraded mode

## Observability

- [ ] Failures produce a log line that identifies the cause
- [ ] New async work has a metric and appears in job records
- [ ] A new alert (if any) links to a runbook section

## Documentation

- [ ] Affected docs updated **only if reality changed** — no new docs unless the item asked for one
- [ ] An architectural decision is recorded as an ADR, with real rejected alternatives
- [ ] An open question that was resolved is removed from the doc and the backlog table
- [ ] The glossary is respected; no new synonyms introduced

---

## The four questions

If the checklist passes but any of these is uncomfortable, the item is not done:

1. **Would a volunteer lose data in any failure mode this change introduces?**
2. **Could a donor number be altered without leaving a trace?**
3. **Could one org see another's data through this path?**
4. **Does this fail honestly, or does it lie to the user?**

These are the four things this product cannot get wrong. Everything else is recoverable.
