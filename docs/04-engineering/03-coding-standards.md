# Coding standards

Rules that are mechanically enforced are marked **[lint]** or **[CI]**. The rest are review criteria. Where a rule
exists to prevent a specific, known failure, the reason is stated — an agent that understands the reason applies
the rule correctly in a case the rule did not anticipate.

---

## 1. TypeScript

- `strict: true`, `noUncheckedIndexedAccess: true`, `exactOptionalPropertyTypes: true`. **[CI]**
- `any` is banned. Use `unknown` plus a narrowing guard. **[lint]**
- Non-null assertion `!` is banned except in tests. **[lint]** It is a claim the compiler cannot check, and it is
  wrong exactly when it matters.
- Prefer `type` over `interface` unless declaration merging is genuinely needed.
- Derive types from Zod schemas (`z.infer`) rather than declaring them twice. One definition validates and types.
- No enums; use `as const` objects with a derived union. TypeScript enums have surprising runtime semantics.
- Explicit return types on exported functions. **[lint]**
- Discriminated unions over optional-field soup. If two shapes are different, model them as different.

```ts
// Good — the type makes the invalid state unrepresentable
type OptimisationResult =
  | { mode: 'optimised'; stops: Stop[]; distanceM: number; engine: string }
  | { mode: 'fallback_straight_line'; stops: Stop[]; reason: string };

// Bad — every consumer must remember which fields go together
type OptimisationResult = {
  mode: string; stops: Stop[]; distanceM?: number; engine?: string; reason?: string;
};
```

## 2. Error handling

- Never swallow an error. Handle it, or let it propagate. **[lint]** on empty `catch`.
- Domain errors are typed classes extending `DomainError`, carrying a problem `type` slug, status and safe detail.
- Infrastructure errors are wrapped with context before rethrowing, never rewritten into a generic message.
- The API's exception filter is the single place that maps errors to RFC 9457 problem documents. A controller never
  formats an error body.
- Never include internal identifiers, SQL, or stack traces in a user-visible `detail` (`NFR-034`).

```ts
export class MicrochipConflictError extends DomainError {
  readonly type = 'https://tnr-os.dev/problems/conflict';
  readonly status = 409;
  constructor(readonly existingAnimalId: string) {
    super('This microchip is already registered to another animal in this organisation.');
  }
}
```

## 3. Async

- `async`/`await` only; no raw `.then()` chains.
- No floating promises. **[lint]** In fire-and-forget cases, `void` the promise explicitly and attach a catch.
- Use `Promise.all` for independent work; sequential `await` in a loop is a review comment unless the sequence is
  required (rate-limited external calls, ordered mutations).
- Every external call has an explicit timeout. A hung request without one holds a connection until the process
  dies.

## 4. Database access

- All queries go through a repository. Services never write SQL. **[lint]**
- Every repository method takes `OrgContext` first. **[lint]**
- Every tenant query filters `org_id` and `deleted_at IS NULL`.
- Parameterised queries only; string-concatenated SQL is banned. **[lint]**
- Reporting reads `intervention_effective`, never `intervention`. **[lint]** in reporting modules — see ADR-0018
  for why this single rule prevents the most likely reporting bug in the product.
- Transactions are explicit and passed as a unit of work. A domain change and its audit event share one
  transaction. **[CI]** via test.
- `ST_DWithin` for proximity, never `ST_Distance` in a `WHERE` clause — the latter cannot use the index and turns
  a map pan into a table scan.

## 5. API layer

- Controllers validate, delegate, map. No business logic, no SQL. **[lint]**
- Every endpoint declares permissions in `<module>.permissions.ts`.
- Request and response shapes are Zod schemas in `<module>.schema.ts`, shared with the client.
- Mutating endpoints accept `Idempotency-Key`.
- No `org_id` from a request body, query or params. **[lint]**

## 6. React

- Function components with hooks. No class components.
- One component per file; the file is named after it.
- Server state through TanStack Query. Never mirror it into a global store — two sources of truth for the same
  data always diverge.
- Local durable state through Dexie; ephemeral state in the component; Zustand only for genuinely cross-cutting UI
  (active org, connectivity, map viewport).
- Custom hooks for logic reused across components; keep components about rendering.
- No `useEffect` for data fetching. Query library, or a route loader.
- Every list has a stable `key` that is not the array index.
- `dangerouslySetInnerHTML` is banned. **[lint]**

**Field-mode specific rules** — these exist because the field client is used cold, with gloves, on a cheap phone:

- No component in `routes/f/**` may import a chart library, a data grid, or the PDF viewer. **[CI]** bundle check.
- Every interactive element in field mode is ≥ 48×48 px (`NFR-061`).
- No blocking spinner on a user action. Apply locally, queue, show status (`05-offline-first-and-sync.md` §9).
- No component may assume it is online.

## 7. Internationalisation

- No hard-coded user-facing strings. **[lint]** Everything goes through the i18n catalogue.
- Keys are hierarchical and descriptive: `capture.form.animal_count.label`.
- Romanian is the primary field locale; English is the development locale; German is report-only.
- CI fails on a missing key for a shipped locale (`NFR-021`).
- Never concatenate translated fragments. Use interpolation with named parameters — word order differs between
  Romanian and German, and concatenation produces nonsense.
- Dates, numbers and units via `Intl`. Coordinates always decimal degrees, locale-independent (`NFR-022`).

## 8. Comments

Comment only what the code cannot say: a constraint, a trade-off, a regulation, a non-obvious performance
consideration, a device quirk.

```ts
// Romanian chips use the 642 country prefix; foreign chips are valid here and
// must not be rejected — a rescued dog may carry a German or Bulgarian chip.
const isRomanianChip = chip.startsWith('642');

// ST_DWithin uses the GIST index; ST_Distance in a WHERE clause does not.
```

Never narrate mechanics (`// increment the counter`), never explain a diff (`// changed to fix the bug`), never
leave a self-congratulatory note. `TODO` requires an ID: `// TODO(TNR-042): …` (`AGENTS.md` §5).

## 9. Logging

- Structured, with a message key and fields — never an interpolated sentence.
- Never log PII, coordinates, tokens, signed URLs, or medical notes (`NFR-034`). Redaction is structural, in the
  logger, not left to call sites.
- `info` for business events, `warn` for self-healing anomalies, `error` for things needing a human.
- Always include `request_id`. Include `org_id` where relevant.

## 10. Testing

Rules live in [`04-testing-strategy.md`](04-testing-strategy.md). The standards that belong here:

- Test names state behaviour: `rejects a sighting with occurred_at more than 24h in the future`.
- Arrange–Act–Assert, with blank-line separation.
- One logical assertion per test; use table-driven tests for variations.
- No shared mutable state between tests.
- Never weaken an assertion to make a test pass. **Fix the code or fix the test's premise** (`AGENTS.md` §11).

## 11. Dependencies

- New runtime dependencies need a one-line justification in the PR description.
- Anything with a native build step, a licence that is not MIT/Apache/BSD, or an EU-residency implication needs an
  ADR.
- Prefer the platform: `Intl`, `crypto`, `fetch`, `URL`, `structuredClone`.
- Pin exact versions in the lockfile; the lockfile is committed.
- No dependency added solely to avoid writing twenty lines.

## 12. Formatting

Prettier with the shared config; ESLint with `--fix` on save. **Never reformat a file you did not otherwise
change** (`AGENTS.md` §5). Formatting churn hides real changes from reviewers and creates conflicts for
concurrent agents.

## 13. Anti-patterns

| Do not | Do instead | Why |
|---|---|---|
| `catch (e) {}` | Handle or propagate | Silent failure is the hardest bug to find |
| `as unknown as T` | Fix the type, or write a real guard | It is a lie to the compiler |
| Business logic in a controller | Put it in the service | The worker calls services, not controllers |
| `SELECT *` in a repository | Name the columns | A new column silently changes every payload |
| A new global store slice | Query cache or local state | Global state is where staleness lives |
| A "utils" dump file | Name the module after its concept | `utils.ts` grows without bound and belongs to nobody |
| Copying a type from the API into the web app | Import from `@tnr/shared` | Copies drift; drift breaks offline clients |
| Refactoring outside your item's `Touches` list | File a backlog item | Concurrent agents collide |
| Editing an applied migration | Add a new migration | Applied migrations are history |
