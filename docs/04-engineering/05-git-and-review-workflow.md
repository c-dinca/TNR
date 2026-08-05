# Git and review workflow

Designed for several agents plus one human working concurrently. The objective is that two agents rarely touch the
same file, and that when they do it is detected before the work is wasted.

---

## 1. Branching

Trunk-based. `main` is always deployable.

```
main
 ├── feat/TNR-042-pack-merge-endpoint
 ├── fix/TNR-051-outbox-duplicate-on-retry
 ├── chore/TNR-018-runbook-scaffold
 └── docs/TNR-120-update-data-model
```

Rules:

- One backlog item, one branch, one PR.
- Branch from current `main`; rebase on `main` rather than merging it in.
- Short-lived — a branch older than three days is a scoping failure; split the item.
- Never commit directly to `main`. Never force-push a branch someone else may have pulled.

## 2. Commits

Conventional Commits, imperative mood, with the item ID:

```
feat(api): add pack merge endpoint (TNR-042)
fix(web): stop outbox duplicating on retry after 401 (TNR-051)
chore(infra): pin postgis image digest (TNR-003)
docs(adr): supersede ADR-0012 with Hetzner hosting (TNR-130)
test(sync): add seven-day soak scenario (TNR-060)
```

Types: `feat`, `fix`, `chore`, `docs`, `test`, `refactor`, `perf`, `build`, `ci`.
Scopes: `api`, `web`, `worker`, `db`, `shared`, `infra`, `contracts`, `adr`, `sync`, `audit`.

Body explains **why** when it is not obvious. Never explain what the diff shows — the diff shows it.

## 3. Pull requests

Title matches the primary commit. Description follows this template:

```markdown
## What
One or two sentences. What now works that did not before?

## Why
Link the backlog item and the requirement IDs it satisfies (FR-###, NFR-###).

## How
Only the non-obvious decisions. Skip the narration.

## Contract changes
- [ ] openapi.yaml changed  (additive? breaking?)
- [ ] migration added       (expand/contract safe? backward compatible with the deployed app?)
- [ ] shared types changed  (who consumes them?)

## Testing
What you added, and how you verified the offline path if it is affected.

## Dependencies added
Name + one-line justification, or "none".

## Risk
What could break, and how it is rolled back.
```

Size guidance: under 400 changed lines is comfortable; over 800 needs a reason in the description. A large PR that
is mostly a generated file or a migration is fine — say so.

## 4. Review

Every PR is reviewed before merge, including a solo founder's own (self-review against this checklist, or a
Bugbot/agent review).

**Blocking checks**

- [ ] Does this violate a contract (`contracts/`) or an accepted ADR? If intentional, is there a new ADR?
- [ ] Is `org_id` derived from the session everywhere, never from client input?
- [ ] Is authorisation enforced in the **service** layer, not only the controller?
- [ ] Does every mutation write an audit event in the same transaction?
- [ ] Does reporting read `intervention_effective`, never the base table?
- [ ] Is the offline path preserved — does anything now require connectivity that did not?
- [ ] Is the migration backward-compatible with the currently deployed app (`NFR-026`)?
- [ ] Are new endpoints covered by the adversarial tenancy suite?
- [ ] Any PII, coordinates, tokens or signed URLs newly reachable by a logger?
- [ ] Does field mode still exclude console-only libraries?

**Non-blocking but expected**

- [ ] Domain vocabulary matches the glossary — no banned synonyms
- [ ] Tests assert effects, not just status codes
- [ ] No unexplained new dependency
- [ ] No formatting churn in untouched files
- [ ] Comments explain constraints, not mechanics

**Second-look rule.** Changes to `apps/api/src/modules/auth`, the audit module, migrations touching
`audit_event` or `intervention`, or anything in `contracts/` require an explicit second review pass, even for the
founder. These are the areas where a mistake is expensive and quiet.

## 5. Merging

Squash merge into `main`, with the PR title as the commit message. Delete the branch. `main` history stays one
commit per item, which makes `git bisect` and rollback straightforward.

## 6. Preventing agent collisions

1. Every backlog item declares a **Touches** list of paths (`../05-delivery/02-backlog.md`).
2. Before starting, check whether an in-progress item overlaps. If it does, **stop and report** rather than editing
   (`AGENTS.md` §3).
3. Contract changes land **first**, alone, in their own item. Consumers follow separately. This is what keeps
   several agents unblocked instead of serialised behind one big PR.
4. Stay inside your item's scope. An unrelated bug becomes a new backlog item, not a drive-by fix.
5. Agent roles map onto directories (`AGENTS.md` §9). Working outside your role's ownership needs an explicit
   reason in the PR.

## 7. Never commit

| Never | Why |
|---|---|
| `.env`, credentials, tokens, private keys | Obvious; enforced by gitleaks in pre-commit and CI |
| Real customer or animal-welfare data, database dumps | It contains locations that can identify households |
| Large binaries (OSM extracts, PMTiles, images > 1 MB) | Repo bloat; these live in object storage |
| `node_modules`, build output, coverage | Gitignored |
| Commented-out code | Git remembers it; delete it |
| A change to an already-applied migration | Applied migrations are history; add a new one |

If a secret is committed: **rotate it first**, then remove it from history. Rotation is the fix; history rewriting
is cleanup.

## 8. Pre-commit hooks

Fast checks only — a slow hook gets bypassed, and a bypassed hook is worse than no hook:

```
lint-staged: eslint --fix, prettier --write
gitleaks: secret scan
commitlint: Conventional Commits format
```

Type-checking and tests belong in CI, not in a pre-commit hook.

## 9. Releases

Continuous deployment to staging on merge; manual promotion to production
(`../02-architecture/09-infrastructure-and-devops.md` §9). No release branches, no version tags on the app in
Phase 1 — the commit SHA is the version, exposed at `/healthz` (`NFR-044`).

`packages/shared` is versioned only if it is ever published externally, which it is not in Phase 1.

## 10. Handling a conflict

```bash
git fetch origin && git rebase origin/main
# resolve, understanding both sides — never blind-accept ours or theirs
pnpm lint && pnpm typecheck && pnpm test
git push --force-with-lease   # your own branch only
```

`--force-with-lease`, never `--force`. If the conflict is in a migration, **do not renumber someone else's**;
add yours with the next free number and verify the sequence applies cleanly from scratch (`pnpm db:reset`).
