# AGENTS.md — operating rules for TNR-OS

This file is the entry point for any AI agent (and any human) working in this repository. Read it fully before
your first edit. It is intentionally prescriptive: multiple agents work on this codebase concurrently, and
consistency matters more than individual preference.

---

## 1. What this project is

TNR-OS is a geospatial command and fleet-logistics SaaS for Trap–Neuter–Return campaigns run by animal-welfare
NGOs in Romania. Phase 1 is software only. See [`README.md`](README.md) and
[`docs/00-context/01-problem-and-vision.md`](docs/00-context/01-problem-and-vision.md).

Two things make this product valuable, and both must be protected by every change you make:

1. **Field data capture works offline.** Volunteers operate in villages with 2G or no signal. If a change makes
   the volunteer flow require connectivity, the change is wrong.
2. **The audit trail is trustworthy.** Donors release six-figure grants based on it. Never allow retroactive,
   unlogged mutation of intervention records or media.

## 2. Source-of-truth hierarchy

When sources conflict, resolve in this order:

1. `contracts/openapi.yaml` and `contracts/db/migrations/*.sql` — normative
2. Accepted ADRs in `docs/03-adr/` — normative for decisions
3. `docs/` — descriptive; if it contradicts a contract, fix the doc
4. Existing code — may be wrong; do not propagate a pattern that contradicts 1–3

Never silently deviate from 1 or 2. To deviate, write a new ADR that supersedes the old one (see §7).

## 3. Before you write code

- [ ] Read the backlog item you are implementing in [`docs/05-delivery/02-backlog.md`](docs/05-delivery/02-backlog.md). Work is only done against a `TNR-###` item.
- [ ] Read the architecture docs listed in that item's **Reading** field. Do not read all of `docs/` — read what the item points to.
- [ ] Check the item's **Touches** field. If another in-progress item touches the same files, stop and report the conflict rather than editing.
- [ ] Confirm the acceptance criteria are testable. If not, sharpen them in the backlog first.

## 4. Non-negotiable engineering rules

**Language and types**

- TypeScript everywhere, `strict: true`. `any` is banned; use `unknown` plus a narrowing guard.
- No implicit `null` handling. Model absence explicitly.
- Shared types live in `packages/shared`. The API is the only producer of wire types; the web app imports them, never redefines them.

**Data**

- Every tenant-scoped table has `org_id` and every query filters on it. There is no "global" read path for tenant data outside of platform-admin endpoints.
- All IDs are UUIDv7, generated **client-side** for offline-created records. The server does not mint IDs for sightings, packs, animals or interventions.
- Timestamps are `timestamptz`, always UTC, named `*_at`. Client-observed time is stored separately from server-received time (`occurred_at` vs `created_at`) — never collapse them.
- Coordinates are `geography(Point, 4326)`. Never store lat/lng as loose floats in new tables.
- Schema changes are forward-only SQL migration files. No ORM-generated migrations, no editing an applied migration.
- Deletes are soft (`deleted_at`) for domain records. Hard delete only via the GDPR erasure path.

**API**

- REST under `/v1`. Errors are RFC 9457 `application/problem+json`. Lists are cursor-paginated.
- All mutating endpoints accept `Idempotency-Key`. Offline replay is normal, not exceptional.
- Additive changes only within `v1`. Removing or narrowing a field requires a version bump and an ADR.

**Security**

- Authorisation is checked in the service layer, not only in controllers or the UI.
- Never log PII, coordinates of a caller's home, JWTs, or media URLs with signatures.
- Secrets come from the environment, validated at boot by a Zod schema. A missing secret must crash on start, not at first use.

**Testing**

- Every backlog item ships with tests. See [`docs/04-engineering/04-testing-strategy.md`](docs/04-engineering/04-testing-strategy.md).
- Business rules are unit-tested; every endpoint has an integration test against a real Postgres+PostGIS container; the offline sync flow has an end-to-end test.
- A PR that lowers coverage on the domain layer is rejected.

## 5. Working style

- **Small, vertical slices.** One backlog item = one PR = migration + API + client + tests. Do not open a PR that adds a table nobody reads.
- **Stay inside your item's `Touches` list.** Found an unrelated bug? File it as a new backlog item and move on.
- **Do not reformat files you did not otherwise change.** Formatting churn destroys reviewability for other agents.
- **Do not add dependencies casually.** New runtime dependencies need a one-line justification in the PR description. Anything with a native build step, or an EU-data-residency implication, needs an ADR.
- **Do not create documentation files unless the item asks for it.** Update the existing doc instead.
- **Leave no TODOs without an ID.** `// TODO(TNR-042): ...` or don't write it.

## 6. Comments and naming

Comment only what the code cannot say: a constraint, a trade-off, a reference to a regulation or a device
quirk. Never narrate mechanics, never explain a diff, never leave "this is now correct" notes.

Domain vocabulary is fixed by [`docs/00-context/03-glossary.md`](docs/00-context/03-glossary.md). Use
`sighting`, `pack`, `animal`, `intervention`, `mission`, `stop`, `org` exactly as defined there — in code,
database, API and UI copy. Do not introduce synonyms (`report`, `colony`, `dog`, `surgery`, `route`, `job`,
`tenant`) for concepts that already have a name.

## 7. Changing a decision

1. Copy `docs/03-adr/0000-template.md` to the next number.
2. Fill in context, options considered with real trade-offs, decision, consequences.
3. Set the superseded ADR's status to `Superseded by ADR-XXXX`.
4. Update affected docs and contracts in the same PR.

An ADR is not a place to record what you did; it records why an alternative was rejected.

## 8. Git and PRs

Branches: `feat/TNR-042-short-slug`, `fix/…`, `chore/…`, `docs/…`.
Commits: Conventional Commits, imperative, scoped — `feat(api): add pack merge endpoint (TNR-042)`.
Never commit directly to `main`. Never force-push a shared branch. Never commit secrets, `.env`, dumps, or
real animal-welfare data — see [`docs/04-engineering/05-git-and-review-workflow.md`](docs/04-engineering/05-git-and-review-workflow.md).

Definition of done: [`docs/05-delivery/04-definition-of-done.md`](docs/05-delivery/04-definition-of-done.md).
Do not mark an item complete until every box is checked.

## 9. Agent roles

Agents should self-assign to one role per task and stay within its boundary. Boundaries exist to prevent two
agents editing the same file.

| Role | Owns | Must not touch |
|---|---|---|
| `infra` | `infra/`, `.github/workflows/`, Dockerfiles, compose files | application source |
| `api` | `apps/api/`, `packages/db/`, migrations | `apps/web/` |
| `web` | `apps/web/` | migrations, `apps/api/` |
| `shared` | `packages/shared/`, `contracts/openapi.yaml` | consumers of the contract in the same PR, unless the item says otherwise |
| `qa` | `apps/*/test/`, `e2e/` | production source (report failures instead of patching) |
| `docs` | `docs/` | code |

A contract change (`shared` role) lands first, on its own, and consumers follow in separate items. This keeps
concurrent agents unblocked.

## 10. Environment expectations

- Node 22 LTS, pnpm 9, Docker with Compose v2.
- `pnpm dev` starts Postgres+PostGIS, Redis, MinIO, API, worker, web. Setup: [`docs/04-engineering/02-local-dev-setup.md`](docs/04-engineering/02-local-dev-setup.md).
- Never run migrations against a non-local database from your own shell.
- Long-running commands (`pnpm dev`, OSRM extraction) belong in the background; do not block on them.

## 11. When you are stuck

Stop after two failed attempts at the same approach. Report: what you tried, what the evidence was, what you
believe the root cause is, and the two most plausible next steps. Do not thrash, do not silently reduce scope,
and do not weaken a test to make it pass.
