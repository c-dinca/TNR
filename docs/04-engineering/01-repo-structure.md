# Repository structure

**This layout is normative.** It is created by `TNR-001` and must not be reshaped without an ADR. Concurrent
agents depend on knowing where things live and who owns them (`AGENTS.md` §9).

---

## 1. Layout

```
tnr-os/
├── AGENTS.md
├── README.md
├── package.json                 workspace root, scripts only
├── pnpm-workspace.yaml
├── turbo.json
├── tsconfig.base.json
├── .env.example
│
├── contracts/                   NORMATIVE — the source of truth
│   ├── openapi.yaml
│   └── db/migrations/*.sql
│
├── docs/                        this documentation set
│
├── apps/
│   ├── api/                     NestJS HTTP service
│   │   ├── src/
│   │   │   ├── main.ts
│   │   │   ├── app.module.ts
│   │   │   ├── common/          guards, interceptors, filters, pipes, decorators
│   │   │   ├── modules/         one folder per domain module
│   │   │   └── config/          env schema, feature flags
│   │   └── test/                integration + adversarial tenancy suites
│   │
│   ├── worker/                  BullMQ processors — imports domain from api
│   │   ├── src/
│   │   │   ├── main.ts
│   │   │   ├── queues/
│   │   │   └── jobs/            one file per job type
│   │   └── test/
│   │
│   └── web/                     React 19 + Vite PWA
│       ├── src/
│       │   ├── main.tsx
│       │   ├── routes/          /f (field) and /c (console)
│       │   ├── features/        vertical slices by domain
│       │   ├── components/      shared presentational
│       │   ├── lib/             api client, dexie, outbox, sync, map, i18n
│       │   ├── locales/         ro.json, en.json, de.json
│       │   └── sw.ts            service worker
│       └── test/
│
├── packages/
│   ├── shared/                  Zod schemas, domain types, generated API types, constants
│   ├── db/                      Drizzle schema, repositories, migration runner, seed
│   ├── config/                  shared eslint, tsconfig, prettier, vitest presets
│   └── ui/                      shared design-system components
│
├── infra/
│   ├── terraform/
│   ├── fly/
│   ├── docker/
│   ├── compose/
│   └── scripts/
│
├── e2e/                         Playwright: offline flows, sync, cross-browser
└── .github/workflows/
```

## 2. Dependency rules

Enforced by `eslint-plugin-boundaries` and by workspace dependencies. A violation fails CI.

```
apps/web      → packages/{shared,ui,config}
apps/api      → packages/{shared,db,config}
apps/worker   → packages/{shared,db,config} + apps/api (domain services only)
packages/db   → packages/{shared,config}
packages/ui   → packages/{shared,config}
packages/shared → packages/config
```

Forbidden, absolutely:

- `apps/web` importing from `apps/api` or `packages/db`. The client never touches server code or the database
  schema; it uses generated types from `packages/shared`.
- `packages/shared` importing anything runtime-specific — no `fs`, no `pg`, no DOM. It runs in a browser, in Node,
  and in a service worker.
- `packages/db` importing HTTP types or NestJS.
- A controller importing a repository directly. Controllers call services; services call repositories.
- Circular imports between packages, at all.

`apps/worker` importing `apps/api` is the one intentional coupling: the worker deliberately reuses the domain
services so business logic exists once (`01-system-overview.md` §3). It imports **services only**, never
controllers, guards or DTOs.

## 3. API module shape

Every module under `apps/api/src/modules/` has the same files, so an agent can navigate a module it has never
read:

```
<module>/
  <module>.module.ts
  <module>.controller.ts       HTTP only: validate, delegate, map response
  <module>.service.ts          business rules, invariants, authorisation decisions
  <module>.repository.ts       data access; takes OrgContext first
  <module>.schema.ts           Zod schemas (request, response, shared with the client)
  <module>.events.ts           domain events emitted
  <module>.permissions.ts      required permission per operation
  __tests__/
    <module>.service.spec.ts
    <module>.controller.int-spec.ts
```

Modules for Phase 1: `auth`, `orgs`, `members`, `invitations`, `sightings`, `packs`, `animals`, `interventions`,
`missions`, `vehicles`, `campaigns`, `grants`, `media`, `reports`, `metrics`, `audit`, `sync`, `jobs`, `admin`,
`devices` (seam only), `health`.

## 4. Web feature shape

```
features/<feature>/
  components/
  hooks/
  api.ts          typed calls using generated types
  offline.ts      Dexie access + outbox enqueue (only where the feature is offline-capable)
  types.ts        feature-local types (domain types come from packages/shared)
  index.ts        public surface of the feature
```

Cross-feature imports go through `index.ts` only. Reaching into another feature's internals is a review
rejection — it is how a codebase becomes impossible for concurrent agents to work in.

Features for Phase 1: `auth`, `capture`, `packs`, `animals`, `missions`, `interventions`, `campaigns`, `reports`,
`admin`, `sync-status`, `map`.

## 5. `packages/shared`

The contract between client and server. It contains:

- Zod schemas for every entity and every API payload — the same objects validate on the device and on the server
  (ADR-0002).
- Domain types inferred from those schemas.
- Types generated from `contracts/openapi.yaml`.
- Constants: enums, permission strings, error `type` slugs, limits.
- Pure domain helpers: microchip validation, coordinate helpers, notch-ratio maths.

It must have **no runtime dependencies** beyond Zod. Anything platform-specific belongs elsewhere. A `fs` import
here breaks the service worker, and the failure appears far from the cause.

## 6. Naming conventions

| Thing | Convention | Example |
|---|---|---|
| Files | `kebab-case.ts` | `mission-stop.service.ts` |
| React components | `PascalCase.tsx` | `SightingCaptureForm.tsx` |
| Types/interfaces | `PascalCase` | `MissionStop` |
| Variables/functions | `camelCase` | `computeNotchRatio` |
| Constants | `SCREAMING_SNAKE_CASE` | `MAX_SYNC_BATCH_SIZE` |
| Database | `snake_case`, singular tables | `mission_stop` |
| API paths | `kebab-case`, plural collections | `/v1/mission-stops` |
| JSON fields | `snake_case` (matches the DB, so no mapping layer can drift) | `animal_count_estimate` |
| Test files | `*.spec.ts`, `*.int-spec.ts`, `*.e2e.ts` | |
| Migrations | `NNNN_description.sql` | `0002_add_campaign.sql` |

Domain vocabulary is fixed by [`../00-context/03-glossary.md`](../00-context/03-glossary.md). Banned synonyms are
listed there and are a review rejection.

## 7. Root scripts

```jsonc
{
  "dev":            "turbo run dev --parallel",
  "build":          "turbo run build",
  "test":           "turbo run test",
  "test:int":       "turbo run test:int",
  "test:e2e":       "playwright test",
  "lint":           "turbo run lint",
  "typecheck":      "turbo run typecheck",
  "db:migrate":     "pnpm --filter @tnr/db migrate",
  "db:seed":        "pnpm --filter @tnr/db seed",
  "db:reset":       "pnpm --filter @tnr/db reset",
  "contracts:gen":  "pnpm --filter @tnr/shared generate-api-types",
  "contracts:check":"pnpm --filter @tnr/shared check-drift",
  "infra:up":       "docker compose -f infra/compose/docker-compose.yml up -d",
  "infra:down":     "docker compose -f infra/compose/docker-compose.yml down"
}
```

## 8. Package naming

Workspace packages are scoped `@tnr/*`: `@tnr/api`, `@tnr/worker`, `@tnr/web`, `@tnr/shared`, `@tnr/db`,
`@tnr/ui`, `@tnr/config`.

## 9. What does not belong in this repo

| Excluded | Where it goes |
|---|---|
| Marketing site | Separate repo |
| Phase 2 firmware | Separate repo when Phase 2 starts |
| Large binary assets (OSM extracts, PMTiles) | Object storage, fetched by scripts; gitignored |
| Real customer data, database dumps | Nowhere near git (`.gitignore`, and see the security doc) |
| Generated API types | Generated at build time; committed only if a CI drift check enforces freshness |
