# Testing strategy

Two properties must never break: **field data is never lost** and **evidence is never silently altered**. The test
suite is weighted accordingly — the pyramid below is deliberately heavier on integration than typical, because the
risky behaviour in this system lives at boundaries (offline queue, database, object storage), not in pure
functions.

---

## 1. Shape

```
            ┌───────────────┐
            │  e2e  ~30      │  Playwright: offline flows, sync, critical journeys
            ├───────────────┤
            │ integration   │  API + real Postgres/PostGIS + Redis + MinIO
            │     ~250      │
            ├───────────────┤
            │    unit       │  domain rules, pure logic, hooks, components
            │     ~600      │
            └───────────────┘
      plus: adversarial tenancy suite (generated, every route)
            contract drift check (OpenAPI vs implementation)
            performance budgets (bundle size, Lighthouse)
```

## 2. Tools

| Layer | Tool |
|---|---|
| Unit (all packages) | Vitest |
| React components | Vitest + Testing Library |
| API integration | Vitest + Testcontainers (`postgis/postgis:16-3.4`, Redis, MinIO) |
| e2e | Playwright (Chromium, WebKit, Android emulation profile) |
| Load | k6 for sync and dashboard endpoints |
| Accessibility | `axe-core` in component and e2e tests |
| Visual | Deferred. Not worth the maintenance at this stage |

**Integration tests run against real PostGIS.** Mocking spatial queries proves nothing: the bugs are in
`ST_DWithin` semantics, index usage, geography-versus-geometry distance units and axis order — none of which a mock
can express.

## 3. What to test at each level

### Unit

- Domain invariants: an intervention cannot be updated; euthanasia requires a justification; a pack close requires
  a reason.
- Pure calculations: notch ratio, coverage, cost per intervention, clustering score.
- Validation: microchip format, `642` prefix detection, `occurred_at` bounds, coordinate ranges.
- State machines: every legal and illegal mission and stop transition.
- Client outbox logic: enqueue, ordering, retry classification, backoff.
- React components: render states, empty states, error states, accessibility.

### Integration

- Every endpoint: happy path, validation failure, permission failure, cross-org attempt.
- Sync: batching, partial success, idempotency, duplicate `op_id`, out-of-order arrival.
- Transactional coupling: force an audit insert failure, assert the domain change rolled back.
- Spatial queries against seeded real Romanian coordinates.
- Media: presign, upload to MinIO, finalise, hash mismatch, quarantine.
- Job handlers invoked directly with a real database.
- Audit chain: append, verify, detect tampering at a known sequence.

### e2e

Only the journeys whose failure would lose a customer:

1. Register → create org → invite a volunteer → accept.
2. Volunteer captures 5 sightings offline → reconnect → all appear for the coordinator, none duplicated.
3. Coordinator builds a mission → optimises → volunteer executes stops offline → outcomes sync.
4. Vet records an intervention with photos → coordinator generates a report → evidence pack verifies.
5. Kill the browser mid-sync → reopen → outbox intact, drains cleanly.
6. Offline map: cache a region → go offline → the map renders and a pin can be placed.

## 4. The suites that carry disproportionate weight

### 4.1 Adversarial tenancy suite (`NFR-030`)

Generated from the OpenAPI route list. For every route and verb: seed org A and org B, authenticate as A, attempt
B's resource, expect `404` or `403`. **A route absent from the suite fails CI**, so coverage cannot silently
regress as endpoints are added.

This is production-critical code (ADR-0016). It is the primary assurance that application-layer tenancy holds.

### 4.2 Offline durability suite

The most valuable tests in the repository, because they cover the failure that loses users:

| Scenario | Assertion |
|---|---|
| Enqueue + local apply, forced transaction abort | Neither the record nor the outbox entry exists — never one without the other |
| Duplicate send of the same `op_id` | Exactly one row; response `duplicate` |
| Process killed mid-drain | Outbox intact on restart, resumes, no duplicates |
| One rejected mutation in a batch of 50 | 49 applied, 1 surfaced, none lost |
| Dexie migration with 500 pending entries | All entries survive |
| Clock skew +2 h and −3 days | Ordering unaffected; skew recorded |
| **7-day soak: 300 mutations, 200 photos** | Everything arrives; memory stays bounded; batching correct |
| Auth expiry mid-drain | Refresh, resume, nothing lost |
| Storage quota exceeded | Graceful warning, no crash, no data loss |

The soak test is the single most valuable case in the suite: it is what a real volunteer produces after a rural
weekend, and it is what breaks naive implementations.

### 4.3 Evidence integrity suite

| Property | Test |
|---|---|
| Chain integrity | 1,000 events, verify; tamper via direct SQL, expect the exact `first_broken_seq` |
| Immutability | Assert the app DB role lacks `UPDATE`/`DELETE` on `audit_event` |
| Append-only interventions | No mutation path exists; a correction creates a supersede chain |
| Effective-view discipline | A corrected intervention is counted exactly once in every metric |
| Report determinism | Generate twice from the same snapshot, diff bytes (`FR-115`) |
| Media hash verification | Upload with a mismatched declared hash, expect quarantine |
| **`VERIFY.md` procedure** | Run our own published verification instructions against a generated pack |

The last one matters more than it looks: if our published verification procedure does not actually work, the
guarantee we sell is theatre.

## 5. Fixtures and data

- **Coordinates** come from one fixture module of real Romanian locations (Pitești, Slatina, Curtea de Argeș, a
  remote village). No random coordinates — reproducibility beats variety.
- **Axis-order guard**: a test asserts every fixture point lies inside Romania's bounding box. A swapped pair lands
  in the Indian Ocean and fails loudly.
- **Builders, not fixtures files**: `aSighting().withCount(4).notched(1).build()`. Tests state only what they care
  about, so adding a required field does not touch 200 tests.
- **Deterministic seeds** everywhere. A flaky test is treated as a failing test.
- **Never** real customer data, not even anonymised, in any test.

## 6. Coverage

| Area | Minimum | Rationale |
|---|---|---|
| Domain services | 90% | Business rules are the product |
| Repositories | 80% | Via integration tests |
| Sync and outbox | **95%** | Data loss is unacceptable |
| Audit and evidence | **95%** | The commercial guarantee |
| React components | 60% | Diminishing returns above this |
| Overall | 75% | |

Coverage is a floor, not a goal. A PR that lowers domain-layer coverage is rejected (`AGENTS.md` §4). A test
written only to raise a number is worse than no test, because it must be maintained.

## 7. Performance tests

| Budget | Enforcement |
|---|---|
| Field bundle ≤ 250 KB gz, console ≤ 600 KB gz (`NFR-004`) | Hard CI failure |
| Field mode imports no chart/grid/PDF library | Bundle composition check |
| FCP ≤ 2.5 s on simulated 3G (`NFR-003`) | Lighthouse CI |
| Sync p95 ≤ 500 ms for 20 mutations (`NFR-002`) | k6, nightly |
| Dashboard ≤ 2 s with 50k interventions (`NFR-007`) | k6 against a seeded large dataset |
| Optimisation ≤ 10 s for 25 stops (`NFR-006`) | Nightly integration |

Load tests run nightly rather than per-PR: they need a large seeded dataset and would make every PR slow.

## 8. CI gates

Per PR (must pass to merge):

```
lint · typecheck · unit · integration · adversarial tenancy · contract drift ·
bundle budget · a11y · secret scan · dependency audit
```

Nightly: e2e across browsers, load tests, Lighthouse, restore drill (weekly), container scan.

## 9. Writing a good test here

```ts
it('rejects a sighting whose occurred_at is more than 24h in the future', async () => {
  const ctx = await seedOrgWithVolunteer();
  const future = addHours(new Date(), 25);

  const res = await api.post('/v1/sightings', aSighting().occurredAt(future).build(), ctx);

  expect(res.status).toBe(422);
  expect(res.body.type).toContain('validation-failed');
  await expect(countSightings(ctx.orgId)).resolves.toBe(0);
});
```

The last assertion is the point: verify the *effect*, not just the response. A `422` with the row written anyway is
a bug the status code alone would hide.

## 10. What we deliberately do not test

| Not tested | Why |
|---|---|
| Third-party library internals | Not our code |
| Generated types | The generator is tested upstream; drift is caught by the contract check |
| Visual pixel regression | High maintenance, low value at this stage |
| Every permutation of every permission | Table-driven representative coverage per role instead |
| Live external providers in PR CI | Fakes in PR runs; the real integration runs nightly |
