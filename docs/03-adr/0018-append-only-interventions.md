# ADR-0018: Append-only interventions with supersede corrections

- **Status**: Accepted
- **Date**: 2026-08-05
- **Affects**: `intervention` table, API, reporting

## Context

An `intervention` is the billable, reportable and auditable unit of the product. A donor report claiming 3,000
sterilisations is a claim about these rows, and money moves on it.

Field reality guarantees mistakes: a vet mistypes a chip number at 3 p.m. on a 40-surgery day; a procedure is
logged against the wrong animal; a cost is entered in the wrong currency. Corrections must be possible.

Corrections must also be impossible to hide.

## Options considered

### Option A — Mutable rows with an audit log

**For:** Simplest; familiar; the audit log records what changed.
**Against:** The current row is the only thing reporting sees, so a silent edit changes a funded number while the
evidence of the change lives in a separate table nobody reading the report will consult. It also creates an
awkward question: if an intervention counted in a submitted grant report is later edited, which number was true?
The data model should make that question answerable without forensics.

### Option B — Full event sourcing for interventions

**For:** Complete history; time travel; rebuild any past state.
**Against:** Substantial complexity — event schemas, versioning, projections, replay — for one entity. Reporting
becomes a projection with its own consistency concerns. Disproportionate to the need.

### Option C — Append-only rows with explicit supersede links

A correction inserts a new row with `supersedes_intervention_id`; the original gets
`superseded_by_intervention_id`. Both are retained forever. Reporting reads a view that excludes superseded and
deleted rows.

**For:** History is in the same table, visible in the same queries an auditor would already run; a correction is a
first-class, timestamped, attributable act rather than a diff hidden in a log; the "which number was true, and
when" question is answerable directly; far simpler than event sourcing.
**Against:** Every reporting query must exclude superseded rows — forget once and numbers inflate; the table grows
with corrections; the UI must present a chain clearly enough that a user understands what they are looking at.

## Decision

**Option C.** Specified in
[`../02-architecture/02-data-model.md`](../02-architecture/02-data-model.md) §3.8.

The mitigation for the main risk is a single hard rule: **all reporting reads the `intervention_effective` view**,
which excludes superseded and soft-deleted rows. Never the base table. This is stated in the data model, in
`AGENTS.md`, and enforced by a lint rule against `from(intervention)` in reporting modules plus a test asserting a
corrected intervention is counted exactly once.

There is no `PATCH` on intervention core fields; the only path is `POST /v1/interventions/{id}/correct`
(`FR-093`).

## Consequences

**Positive** — a donor number can always be reconciled with what was claimed at the time; corrections are
attributable and visible; combined with the hash chain (ADR-0014), silently altering a funded figure is
effectively impossible; the model is far simpler than event sourcing.

**Negative** — the "always use the effective view" rule is easy to violate and is therefore protected by lint and
tests; the table grows with corrections; the UI must explain supersede chains, which is genuine design work rather
than a table row.

**Neutral** — the same pattern applies naturally to media versioning (`supersedes_media_id`), giving one
consistent correction idiom across the evidence surfaces.

## Revisit when

Correction volume makes chains hard to present, or a customer needs a bulk-correction workflow (a whole campaign
day logged against the wrong campaign) that would produce thousands of supersede rows.
