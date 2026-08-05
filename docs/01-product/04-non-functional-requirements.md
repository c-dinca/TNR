# Non-functional requirements

Every requirement here is a budget or a gate, not an aspiration. If a number cannot be measured in CI or in
production telemetry, it is written wrong and should be fixed.

Blocks: 001–009 performance · 010–019 offline & resilience · 020–029 availability, backup, i18n ·
030–039 security · 040–049 operability · 050–059 cost & scale · 060–069 accessibility & UX.

---

## Performance (001–009)

| ID | Requirement | Measured by |
|---|---|---|
| NFR-001 | The minimal sighting-capture flow MUST complete in ≤ 15 s wall-clock and ≤ 4 taps on a mid-range Android device (Moto G-class, 4 GB RAM). | Scripted e2e run on throttled device profile |
| NFR-002 | The sync endpoint MUST respond in ≤ 500 ms at p95 for a batch of 20 mutations, excluding media. Clustering and other derivations MUST be asynchronous. | API histogram, `/v1/sync` route |
| NFR-003 | First contentful paint on the field PWA MUST be ≤ 2.5 s on a cold cache over simulated 3G (400 kbps, 400 ms RTT); ≤ 1 s on repeat visit. | Lighthouse CI budget |
| NFR-004 | Initial JS transferred for the field route MUST be ≤ 250 KB gzipped; the console route ≤ 600 KB gzipped, map library excluded and lazily loaded. | Bundle-size check in CI, hard fail |
| NFR-005 | Offline tile cache MUST be bounded to a configurable budget, default 150 MB, with a warning at 80%. | Unit test on the cache manager |
| NFR-006 | Route optimisation for ≤ 25 stops MUST return in ≤ 10 s at p95; ≤ 60 stops MUST be queued with progress reporting. | Worker job duration metric |
| NFR-007 | Campaign dashboard MUST render in ≤ 2 s at p95 with 50,000 interventions and 5,000 packs in the org. | Load test with seeded dataset |
| NFR-008 | Map viewport queries MUST return in ≤ 300 ms at p95 for a bounding box containing ≤ 2,000 features, using clustering above that. | API histogram, spatial routes |
| NFR-009 | Report generation MUST complete in ≤ 60 s at p95 for a 12-month, 5,000-intervention campaign. | Worker job duration metric |

## Offline and resilience (010–019)

| ID | Requirement |
|---|---|
| NFR-010 | The field PWA MUST be fully installable and MUST launch and operate with zero network connectivity, given a previously authenticated session. |
| NFR-011 | A valid session MUST survive ≥ 90 days without network re-authentication, so a volunteer never meets a login wall in the field. |
| NFR-012 | The outbox MUST persist across app restart, browser kill, OS restart and forced power loss; durability is verified by a test that kills the process mid-queue. |
| NFR-013 | Outbox replay MUST be idempotent under duplicate delivery, out-of-order delivery, and partial failure; verified by a fault-injection test suite. |
| NFR-014 | Media upload MUST resume after interruption and MUST retry with exponential backoff and jitter, capped at 6 hours between attempts. |
| NFR-015 | The client MUST tolerate a server API version newer than itself for additive changes, and MUST prompt for update when it receives an incompatibility signal. |
| NFR-016 | No single third-party outage (routing engine, microchip lookup, email, tile host) may prevent sighting capture, sync, or intervention recording. Each integration MUST have a documented degraded mode. |
| NFR-017 | The client MUST never lose user input on a failed request; forms MUST be recoverable after a crash. |
| NFR-018 | Clock skew on client devices MUST be detected and recorded; server MUST NOT trust client clocks for ordering, only for `occurred_at` display and evidence. |

## Availability, backup, localisation (020–029)

| ID | Requirement |
|---|---|
| NFR-020 | Target availability of the write API is **99.5%** monthly, excluding announced maintenance. Read-only degradation is preferred to full outage. |
| NFR-021 | The entire user-facing UI MUST be fully localised in Romanian and English; donor reports additionally in German. No hard-coded user-facing strings; CI fails on a missing key for a shipped locale. |
| NFR-022 | Dates, numbers and units MUST follow user locale. Coordinates MUST always be decimal degrees, 6 decimal places, locale-independent. |
| NFR-023 | RPO ≤ 15 minutes, RTO ≤ 4 hours. Daily automated backups with point-in-time recovery; a restore rehearsal MUST be performed and documented quarterly. |
| NFR-024 | Object storage MUST have versioning enabled so an accidental overwrite or delete of evidence media is recoverable for ≥ 30 days. |
| NFR-025 | Planned maintenance MUST NOT interrupt field capture: the client's offline mode is the maintenance strategy. |
| NFR-026 | Database migrations MUST be backward-compatible with the previously deployed application version, enabling rollback without data loss. |

## Security (030–039)

| ID | Requirement |
|---|---|
| NFR-030 | Cross-tenant isolation MUST be verified by an automated suite that attempts unauthorised access on **every** endpoint; CI fails on any success. |
| NFR-031 | All traffic MUST be TLS 1.2+; HSTS enabled; no mixed content. |
| NFR-032 | Secrets MUST come from the environment, be validated by schema at boot, and be absent from source, logs and error reports. A missing secret MUST crash at boot. |
| NFR-033 | Dependency vulnerabilities: CI MUST fail on known critical/high advisories in production dependencies. |
| NFR-034 | Logs MUST NOT contain passwords, tokens, signed URLs, precise coordinates tied to a private residence, or free-text medical notes. |
| NFR-035 | Rate limiting MUST be applied per IP and per identity on authentication, sync, media presign and export endpoints. |
| NFR-036 | All personal data MUST be stored and processed in EU regions; a non-EU region in infrastructure config MUST fail CI. |
| NFR-037 | Audit log storage MUST be append-only at the application layer, with no update or delete path exposed to any role. |
| NFR-038 | Content-Security-Policy MUST be enforced without `unsafe-inline` for scripts; the PWA service worker scope MUST be explicit. |

## Operability (040–049)

| ID | Requirement |
|---|---|
| NFR-040 | All services MUST emit structured JSON logs with a correlation ID propagated from the client request through workers. |
| NFR-041 | The system MUST expose RED metrics (rate, errors, duration) per route and per background job, plus domain metrics (sightings/day, sync failures, outbox age). |
| NFR-042 | Unhandled errors MUST reach an error tracker with release version and user org, and without PII. |
| NFR-043 | Alerting MUST be tuned for a solo operator: at most 2 pageable alerts per week in steady state. Anything noisier is a bug in the alert. |
| NFR-044 | Every deployment MUST be traceable to a commit SHA exposed at `/healthz` and in error reports. |
| NFR-045 | Rollback of the application MUST be possible in ≤ 5 minutes without a database restore. |
| NFR-046 | A single command MUST bring up a complete local environment with realistic seed data. |
| NFR-047 | Background job failures MUST be visible, retryable and bounded; a permanently failing job MUST land in a dead-letter view, not vanish. |

## Cost and scale (050–059)

| ID | Requirement |
|---|---|
| NFR-050 | Total infrastructure cost MUST remain under €150/month until the third paying org. |
| NFR-051 | The system MUST support, without architectural change: 50 orgs, 2,000 users, 500,000 sightings, 200,000 interventions, 5,000,000 media objects. |
| NFR-052 | Media egress MUST be minimised through derivatives and short-lived signed URLs; evidence packs MUST stream rather than buffer whole archives in memory. |
| NFR-053 | Map tiles MUST NOT incur per-request commercial fees at Phase 1 volumes. |
| NFR-054 | A single org's heavy usage (bulk import, large report) MUST NOT degrade another org's interactive latency; heavy work goes to queues with per-org fairness. |

## Accessibility and field usability (060–069)

| ID | Requirement |
|---|---|
| NFR-060 | The UI MUST meet WCAG 2.1 AA for contrast, focus order, labels and keyboard operability on the console; automated axe checks run in CI. |
| NFR-061 | Primary field actions MUST have touch targets ≥ 48×48 px and MUST be operable one-handed with gloves. |
| NFR-062 | The field UI MUST remain legible in direct sunlight: minimum 4.5:1 contrast, no information conveyed by colour alone. |
| NFR-063 | Every destructive action MUST be confirmable and, for domain records, reversible for ≥ 30 days via soft delete. |
| NFR-064 | Every asynchronous operation MUST show state honestly: queued, running, failed with reason. No indefinite spinners. |
| NFR-065 | The field UI MUST minimise battery drain: no continuous GPS polling, no background location tracking; position is sampled on demand. |

---

## Explicit non-requirements

Stating these prevents over-engineering:

- **No horizontal multi-region deployment.** Single EU region is sufficient for Phase 1.
- **No sub-second real-time collaboration.** Coordinator views may be up to 5 minutes stale.
- **No 99.9%+ availability.** Offline-first clients absorb short outages by design; buying another nine is not worth the cost at this stage.
- **No native mobile apps.** PWA only, until push notifications or BLE force the question in Phase 2.
- **No self-service billing.** Manual invoicing until roughly ten customers.
