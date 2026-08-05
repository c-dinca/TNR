# CI/CD

Principle: **CI is fast enough that nobody wants to skip it, and strict enough that `main` is always
deployable.** Target: under 8 minutes for the PR pipeline.

---

## 1. Pipelines

| Workflow | Trigger | Purpose |
|---|---|---|
| `pr.yml` | PR opened/updated | Fast quality gate |
| `main.yml` | Push to `main` | Build, publish images, deploy staging, smoke |
| `deploy-prod.yml` | Manual dispatch | Promote a specific SHA to production |
| `nightly.yml` | Schedule | e2e across browsers, load, Lighthouse, container scan |
| `weekly.yml` | Schedule | Restore drill, dependency review, cost report |

## 2. PR pipeline

```
setup (Node 22, pnpm, Turborepo remote cache)
  ├─ lint            eslint + prettier check + boundary rules
  ├─ typecheck       tsc --noEmit, all packages
  ├─ unit            vitest, all packages
  ├─ contracts       OpenAPI validity + implementation drift + Drizzle/SQL schema drift
  ├─ security        gitleaks, pnpm audit (critical/high), semgrep
  └─ integration     Testcontainers: postgis + redis + minio
        ├─ API integration suite
        ├─ adversarial tenancy suite   ← fails if a route is uncovered
        └─ migration replay from scratch
  └─ web-budget      bundle size + field-mode composition + axe
```

All jobs run in parallel where dependencies allow. Turborepo's cache means an unchanged package is not re-tested.

**Every one of these is blocking.** A red pipeline is not merged, and a flaky test is treated as a failing test —
quarantining it silently is how a suite becomes worthless.

## 3. Specific gates and why they exist

| Gate | Fails when | Prevents |
|---|---|---|
| Boundary lint | `apps/web` imports `apps/api`; a controller imports a repository | Architectural erosion (ADR-0001) |
| Contract drift | Implementation and `openapi.yaml` disagree | The generated client silently diverging from the server |
| Schema drift | Drizzle schema and migrated database disagree | Types that lie about the database (ADR-0005) |
| Migration replay | Migrations do not apply cleanly from empty | A broken migration sequence discovered in production |
| Adversarial tenancy | Any cross-org access succeeds, **or a route is not covered** | The worst non-integrity failure (`NFR-030`) |
| Bundle budget | Field > 250 KB gz or console > 600 KB gz | A field client too heavy for 2G (`NFR-004`) |
| Field composition | Field mode imports a chart/grid/PDF library | Silent bundle creep past the budget |
| i18n completeness | A key is missing for a shipped locale | Romanian volunteers seeing English (`NFR-021`) |
| EU region check | A non-EU region string in infrastructure config | A GDPR residency breach (`NFR-036`) |
| Secret scan | A credential pattern in the diff | Leaked secrets |
| Dependency audit | Critical/high advisory in a production dependency | Known vulnerabilities (`NFR-033`) |

The region check deserves its place: a single copy-pasted `us-east-1` would be a compliance incident, and it is
exactly the kind of mistake a tired operator makes at 2 a.m.

## 4. Main pipeline

```
1. Re-run the PR gate (the merge result may differ from the branch)
2. Build images: api, worker, web static — tagged with the commit SHA
3. Push to the registry
4. Deploy staging:
     a. run migrations (dedicated job, migration DB role)
     b. deploy api  (rolling, health-gated)
     c. deploy worker
     d. publish web static
5. Smoke tests against staging
6. Report status
```

Production is **never** deployed automatically. A human dispatches `deploy-prod.yml` with a SHA that is green on
staging.

## 5. Migration safety

Migrations run as a separate job before the application rolls out. Every migration must be backward-compatible
with the currently deployed application version (`NFR-026`) — that is what makes a five-minute rollback possible
without a database restore (`NFR-045`).

```
Expand   → add nullable column / new table. Deploy. Old code unaffected.
Migrate  → backfill in batches. Deploy code writing both, reading new.
Contract → drop the old column in a LATER release.
```

CI checks that a migration does not: drop a column, rename a column, add `NOT NULL` without a default, or add an
index without `CONCURRENTLY` on a table above a size threshold. Each is overridable with an explicit
`-- migration-allow: <reason>` comment, which forces the author to state the justification where a reviewer will
see it.

## 6. Rollback

| Failure | Response |
|---|---|
| Bad application deploy | Redeploy the previous image tag. ≤ 5 min, no database work |
| Bad migration, expand phase | Usually harmless; roll back the app and write a corrective migration |
| Bad migration, destructive phase | This is why destructive changes are a separate, later release |
| Silent data corruption | PITR restore to a point before the deploy; audit log identifies the window |

Rollback is rehearsed as part of the quarterly drill, not improvised during an incident.

## 7. Nightly and weekly

**Nightly**: full e2e across Chromium/WebKit/Android emulation; k6 load tests for sync and dashboard against a
seeded large dataset; Lighthouse against staging; Trivy container scan; live external-integration tests (OSRM,
chip lookup) that are faked in PR runs.

**Weekly**: restore drill (restore the latest backup into a scratch database and verify integrity, `NFR-023`);
dependency review; cost report against the `NFR-050` budget.

Nightly failures create an issue rather than paging. They are quality signals, not outages.

## 8. Secrets in CI

Repository secrets, never in workflow files. Deploy credentials are scoped per environment; production deployment
requires an environment approval. Fork PRs never receive secrets — integration tests use Testcontainers and fakes,
so nothing in the PR gate needs a real credential.

## 9. Caching

- pnpm store, keyed by lockfile hash.
- Turborepo remote cache, keyed by input hashes.
- Docker layer cache with buildx.
- Playwright browsers cached by version.

Cache invalidation is deliberately conservative: a wrong cache hit is worse than a slow pipeline, because it means
tests passed against code that was not tested.

## 10. Branch protection on `main`

- All PR-gate checks must pass.
- One approving review.
- Branch must be up to date with `main`.
- Linear history (squash merge).
- No force-push, no deletion.
- Administrators are **not** exempt. A solo founder bypassing their own gates is how the gates stop meaning
  anything.

## 11. Ownership

`.github/workflows/` belongs to the `infra` agent role (`AGENTS.md` §9). Changes there need the same review rigour
as production code — a weakened gate is a silent, permanent reduction in quality, and it is the change least
likely to be noticed in review.
