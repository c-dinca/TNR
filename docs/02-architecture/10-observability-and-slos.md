# Observability and SLOs

Designed for **one operator with a day job's worth of other responsibilities**. The design goal is not
comprehensive telemetry; it is that a real problem reaches the founder and a non-problem never does
(`NFR-043`).

---

## 1. Principles

1. **Alert on user-visible symptoms, not causes.** "Sync error rate above 2%" pages. "CPU at 80%" does not.
2. **Every alert has a runbook entry.** An alert without a documented response is a notification, and
   notifications get muted.
3. **Correlate by request ID** from client through API through worker.
4. **Never log sensitive data.** No PII, no coordinates, no medical notes, no tokens, no signed URLs
   (`NFR-034`).
5. **Cardinality is a cost.** Never label a metric with a user id, an entity id, or a coordinate.

## 2. Logging

Structured JSON, one line per event, to stdout; the platform ships them.

```json
{
  "ts": "2026-08-05T09:12:34.001Z",
  "level": "info",
  "msg": "sync.batch.applied",
  "request_id": "01J8K9...",
  "org_id": "01J8...",
  "user_id": "01J8...",
  "route": "POST /v1/sync",
  "status": 200,
  "duration_ms": 187,
  "mutations": { "applied": 18, "duplicate": 2, "rejected": 0 },
  "client": "web-field/1.4.2",
  "commit": "a1b2c3d"
}
```

| Level | Use |
|---|---|
| `error` | Needs a human eventually. Unhandled exception, terminal job failure, hash mismatch |
| `warn` | Self-healing but notable. Retry exhausted on a non-critical path, degraded routing fallback |
| `info` | Business events: sync batches, mission optimised, report generated, membership changed |
| `debug` | Local and staging only. Never enabled in production by default |

**Redaction is structural, not best-effort.** A serialiser strips known-sensitive keys (`password`, `token`,
`authorization`, `signed_url`, `location`, `coordinates`, `health_note`, `complication_note`, `justification`,
`microchip`) at the logger level. A test asserts that a payload containing each of these produces a log line
without it, so a new call site cannot leak by forgetting.

`org_id` and `user_id` are logged as opaque UUIDs. That is operationally necessary and not itself identifying
without database access.

## 3. Metrics

Prometheus-style, exposed at `/metrics` (internal only), scraped by the platform.

**Golden signals per route**

| Metric | Labels |
|---|---|
| `http_requests_total` | route, method, status_class |
| `http_request_duration_seconds` (histogram) | route, method |
| `http_in_flight_requests` | — |

**Jobs**

| Metric | Labels |
|---|---|
| `job_processed_total` | queue, outcome |
| `job_duration_seconds` (histogram) | queue |
| `job_queue_depth` | queue |
| `job_oldest_waiting_seconds` | queue |

**Domain metrics** — the ones that actually indicate product health:

| Metric | Why it matters |
|---|---|
| `sightings_created_total{source}` | Field adoption. A drop means volunteers stopped |
| `sync_batches_total{outcome}` | The core write path |
| `sync_mutations_total{status}` | `rejected` rising means a client/server contract problem |
| `sync_client_outbox_age_seconds` (reported by clients) | Data sitting undelivered on phones |
| `interventions_created_total{type}` | The billable unit |
| `media_upload_total{outcome}` | Evidence capture health |
| `media_hash_mismatch_total` | **Security signal.** Should always be zero |
| `optimisation_total{mode}` | `fallback_straight_line` rising means routing is degraded |
| `audit_chain_verify_failures_total` | **Integrity signal.** Should always be zero |
| `metric_projection_age_seconds` | Dashboard honesty (`FR-112`) |
| `cross_org_access_denied_total` | Tenancy probing |

Client-reported metrics (outbox age, sync failures) arrive on a low-frequency beacon batched with sync. Without
them we would be blind to the failure mode that matters most: data stuck on a phone, where the server sees nothing
at all and everything looks healthy.

## 4. Tracing

OpenTelemetry, sampled: 100% of errors, 100% of `/v1/sync`, 5% of everything else. Trace context propagates from
the client `X-Request-Id` into jobs, so an "optimisation took 40 s" complaint resolves to a specific OSRM matrix
call.

Full tracing is deliberately not enabled everywhere in Phase 1 — the cost and noise exceed the value at this
scale. Sync and errors are traced because they are where the product actually breaks.

## 5. Error tracking

Sentry (or equivalent) for API, worker and web. Release = commit SHA (`NFR-044`). Errors carry `org_id`,
`request_id`, route and client version — and **no PII** (`NFR-042`). `beforeSend` runs the same redaction as the
logger.

Client-side capture includes offline-specific context that is otherwise invisible: outbox depth, connectivity
state, storage quota usage, Dexie schema version. A crash on a phone with a full disk and 200 queued items is a
different bug from the same stack trace on a coordinator's laptop.

## 6. SLOs

| SLO | Target | Window | Measured |
|---|---|---|---|
| Write API availability | 99.5% (`NFR-020`) | 30 d rolling | Non-5xx on `POST /v1/**` |
| Sync latency | p95 ≤ 500 ms (`NFR-002`) | 7 d | `/v1/sync` histogram |
| Sync success rate | ≥ 99% of mutations applied-or-duplicate | 7 d | `sync_mutations_total` |
| Console read latency | p95 ≤ 1 s | 7 d | `GET /v1/**` histogram |
| Dashboard freshness | ≤ 5 min at p99 (`FR-112`) | 7 d | `metric_projection_age_seconds` |
| Media upload success | ≥ 98% within 24 h of capture | 7 d | `media_upload_total` |
| Report generation | p95 ≤ 60 s (`NFR-009`) | 30 d | `job_duration_seconds{queue="generate-report"}` |
| Audit chain integrity | 100% | always | Nightly verification |

Error-budget policy: burning more than 50% of the monthly budget freezes feature work until reliability work
restores it. With one operator this is a rule against oneself, and it is the only thing that prevents a slow slide
into unreliability.

## 7. Alerts

**Pageable** (immediate, phone):

| Alert | Condition |
|---|---|
| API down | Health check failing 2 min |
| Sync failing | 5xx rate on `/v1/sync` > 5% for 5 min |
| Database unreachable | Connection errors > 10 in 1 min |
| Audit chain broken | Any verification failure |
| Media hash mismatch | Any occurrence |
| Cross-org access succeeded | Any occurrence (should be impossible) |

**Ticket** (next working day):

| Alert | Condition |
|---|---|
| Queue backlog | `job_oldest_waiting_seconds` > 900 for 15 min |
| Projection stale | `metric_projection_age_seconds` > 1800 |
| Routing degraded | `optimisation_total{mode="fallback_straight_line"}` > 20% over 1 h |
| Media backlog | Uploads pending > 6 h above baseline |
| Error-rate elevation | Any route's 5xx rate > 1% for 30 min |
| Cost anomaly | Storage or egress > 150% of the 7-day mean |
| Certificate expiry | < 14 days |
| Backup verification failed | Any occurrence |

Six pageable alerts, deliberately. Every one is either "the product is down" or "the integrity guarantee is
compromised". Anything else can wait until morning, and pretending otherwise just trains the operator to ignore
their phone.

## 8. Dashboards

**Operator dashboard** (daily glance): sync rate and errors, queue depths, API latency, error count by route, cost
trend, projection freshness.

**Product dashboard** (weekly): sightings per active volunteer, interventions per week per org, mission completion
rate, planned vs. actual distance saved, media upload success, active volunteers per org, per-org last-activity
(a customer that stopped syncing is churning and nobody has told us yet).

The second dashboard is the more valuable one. A silently churning customer is a bigger problem than a 4xx spike.

## 9. Health endpoints

| Endpoint | Semantics |
|---|---|
| `/healthz` | Process alive. Returns commit SHA and version. Never touches the database |
| `/readyz` | Dependencies reachable (Postgres, Redis). Gates the load balancer |
| `/metrics` | Prometheus exposition, internal only |

`/healthz` must not check the database. A database blip should not cause a deploy to be rolled back or every
container to be killed simultaneously.

## 10. Runbooks

Each alert links to a runbook section in `docs/runbooks/` (created with `TNR-018`) containing: symptom, likely
causes ordered by probability, diagnostic commands, remediation, and escalation. Written for a tired operator at
3 a.m. — commands to copy, not principles to reason from.

Initial set: API down, database unreachable, sync failures, queue backlog, audit chain broken, media hash
mismatch, deploy rollback, restore from backup, secret rotation, OSRM graph refresh.

## 11. What we deliberately do not build

| Not built | Why |
|---|---|
| Log aggregation platform (ELK) | Platform log tail plus Sentry covers a three-service system |
| APM with continuous profiling | Sampled traces are enough at this scale |
| Custom status page | Hosted status page, updated manually |
| Real-time user session replay | Privacy-hostile with field volunteers; low value against the cost |
| Synthetic monitoring beyond uptime checks | Smoke tests in CI plus uptime checks suffice |
| On-call rotation tooling | One person, one phone |

Each of these becomes worth revisiting at roughly ten customers or a second engineer, whichever comes first.
