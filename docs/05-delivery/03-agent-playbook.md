# Agent playbook

How to take an item from `todo` to `done` without colliding with another agent or eroding the architecture.

Read [`../../AGENTS.md`](../../AGENTS.md) first. This document is the procedure; that one is the rules.

---

## 1. Pick up an item

```
1. Open docs/05-delivery/02-backlog.md
2. Choose an item with status `todo` whose "Blocked by" items are `done`
3. Check every in-progress item's "Touches" list for overlap with yours
   → overlap? STOP. Report it. Pick a different item.
4. Set the item's status to `in-progress` and commit that change first, on your branch
5. Read exactly the docs in the item's "Reading" field
6. Create the branch: feat/TNR-0XX-short-slug
```

Do not read all of `docs/`. The Reading list exists because context is finite and reading the wrong things
displaces the right ones.

## 2. Before writing code

Answer these to yourself. If you cannot, the item is not ready and you should sharpen it in the backlog first.

- What does the user see or get that they did not before?
- Which `FR-###`/`NFR-###` does this satisfy, and how will a test demonstrate it?
- Does a contract change (`contracts/`)? If so, it must be its **own item**, landed first.
- Does this touch an offline path? If so, what happens when the device is offline mid-operation?
- Does this touch a mutation? Then it needs an audit event in the same transaction.
- Does this touch tenant data? Then `org_id` comes from the session and the tenancy suite must cover it.

## 3. Implementation order

Vertical slice, bottom up. This ordering surfaces schema mistakes while they are cheap:

```
1. Migration (if needed)   → contracts/db/migrations/NNNN_*.sql, hand-written, forward-only
2. Drizzle schema          → packages/db, then run the schema-drift check
3. Shared schemas          → packages/shared, Zod, used by BOTH sides
4. Repository              → OrgContext first, org_id filter, deleted_at filter
5. Service                 → business rules, invariants, authorisation, audit event
6. Controller              → validate, delegate, map. Nothing else
7. OpenAPI                 → contracts/openapi.yaml, then pnpm contracts:gen
8. Client                  → feature slice; offline path if applicable
9. Tests                   → at every level the testing strategy requires
10. Docs                   → update the affected doc IF this changed reality. Do not create new docs
```

## 4. While working

**Stay in scope.** Found an unrelated bug? New backlog item. Found a tempting refactor? New backlog item. Your
`Touches` list is a contract with the other agents.

**Do not reformat untouched files.** Formatting churn hides your real change and creates conflicts.

**Commit in logical steps** with Conventional Commit messages and the item ID.

**Check in when you learn something load-bearing** — a doc is wrong, a requirement is untestable, an approach does
not work. Say so early rather than absorbing it silently.

## 5. When you are stuck

Stop after **two** failed attempts at the same approach. Then report:

1. What you were trying to achieve.
2. What you tried, and the actual evidence (error, test output, measurement — not a guess).
3. What you believe the root cause is.
4. The two most plausible next steps.

Do not thrash. Do not silently reduce scope. **Never weaken a test to make it pass** — if a test is wrong, say
why and fix its premise explicitly.

## 6. Finishing

```
1. Work through docs/05-delivery/04-definition-of-done.md, every box
2. pnpm lint && pnpm typecheck && pnpm test && pnpm test:int
3. Rebase on main, resolve conflicts understanding both sides
4. Open a PR using the template in 04-engineering/05-git-and-review-workflow.md
5. Set the item's status to `review` in the backlog
6. After merge, set it to `done`
```

## 7. Role boundaries

From `AGENTS.md` §9. One role per task; stay inside it.

| Role | Owns | Never touches |
|---|---|---|
| `infra` | `infra/`, workflows, Dockerfiles | application source |
| `api` | `apps/api/`, `packages/db/`, migrations | `apps/web/` |
| `web` | `apps/web/` | migrations, `apps/api/` |
| `shared` | `packages/shared/`, `contracts/openapi.yaml` | consumers, unless the item says so |
| `qa` | `apps/*/test/`, `e2e/` | production source — report failures, do not patch them |
| `docs` | `docs/` | code |

**Contract changes land alone, first.** An item that changes `contracts/openapi.yaml` does only that plus the
generated types. Consumers follow in separate items. This is what lets several agents work in parallel instead of
queueing behind one large PR.

## 8. Working with the documentation

| Situation | Action |
|---|---|
| A doc contradicts a contract | The contract wins. Fix the doc in your PR |
| A doc contradicts the code | Investigate: usually the code is wrong. If the code is right, the doc lied — fix it |
| A doc is silent on something you need | It is **not decided**. Do not invent silently: decide and record it, in an ADR if it is architectural |
| You hit an **Open question** block | Do not answer it inline. Resolve it in an ADR or escalate. These are marked because getting them wrong is expensive |
| You want to change a decision | New ADR superseding the old one, per `AGENTS.md` §7 |
| You want to add a new doc | Almost always wrong. Update an existing one |

## 9. Common mistakes in this codebase

Ranked by how often they are likely to happen:

1. **Reading `intervention` instead of `intervention_effective`** in a reporting query. Inflates donor numbers.
   Lint catches it; understand why it exists (ADR-0018).
2. **Forgetting the audit event**, or writing it outside the transaction. Breaks the guarantee that sells the
   product.
3. **Taking `org_id` from a request body.** The worst class of bug in this system.
4. **Swapping latitude and longitude.** Every coordinate is `[lon, lat]`. Pitești becomes the Indian Ocean.
5. **Making a field path require connectivity.** Ask, every time: what happens with the radio off?
6. **`ST_Distance` in a `WHERE` clause** instead of `ST_DWithin`. Turns a map pan into a table scan.
7. **Importing a heavy library into field mode.** Blows the 250 KB budget; CI catches it, but late.
8. **Editing an applied migration** instead of adding a new one.
9. **Inventing a synonym** for a glossary term. `dog`, `colony`, `surgery`, `route` are all banned.
10. **Defaulting an unknown actual to zero** instead of leaving it unknown. Fabricates data in a report.

## 10. Quality bar

Ask before opening a PR:

- Would a reviewer understand **why**, not just what, from the diff and description?
- If this breaks in production at 3 a.m., is there a log line or metric that points at it?
- Does the failure mode degrade honestly, or does it lie to the user?
- Have I made a future change harder in a way I did not flag?
- Is there anything here I would be embarrassed to explain to the person who has to maintain it?

The last one is the real test.
