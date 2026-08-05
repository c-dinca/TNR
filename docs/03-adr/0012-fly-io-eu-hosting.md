# ADR-0012: Containers on Fly.io Frankfurt, EU-only residency

- **Status**: Accepted
- **Date**: 2026-08-05
- **Affects**: `infra/`, CI/CD, all deployables

## Context

Three deployable units plus a routing container. One operator. Budget under €150/month (`NFR-050`). EU data
residency is a legal requirement (`FR-124`, `NFR-036`). Availability target is 99.5% write availability
(`NFR-020`) — offline clients absorb short outages by design, so heroic availability engineering is not warranted.

## Options considered

### Option A — AWS ECS Fargate + RDS + S3

**For:** The safe institutional choice; every service available; eu-central-1 satisfies residency.
**Against:** Cost floor well above budget once NAT gateways, ALB and RDS are counted; substantial Terraform surface
for one person to maintain; IAM complexity that becomes its own operational burden. Correct at scale, wrong at
this stage.

### Option B — Kubernetes (EKS/GKE or self-managed)

**For:** Portable, standard, powerful.
**Against:** Operational cost vastly exceeds the benefit for three services. A solo founder maintaining a cluster is
a founder not building the product.

### Option C — Hetzner VPS with Docker Compose

**For:** Cheapest by a wide margin; German data centres; total control.
**Against:** We own the host: patching, monitoring, backup, and a manual failover story. Deploys become bespoke
scripts. Attractive, and genuinely tempting on cost, but the operational surface is exactly what one person cannot
sustain alongside product work.

### Option D — Fly.io, Frankfurt region

**For:** `fly deploy` from a Dockerfile; Frankfurt available; scale-to-few is cheap; built-in health checks,
rolling deploys, secrets, private networking and metrics; excellent fit for a small container set.
**Against:** A smaller vendor with a public history of platform incidents; managed Postgres offering is less mature
than a dedicated provider's; less mature IAM and audit tooling.

### Option E — Render / Railway

**For:** Similar ergonomics, slightly more polished managed database.
**Against:** Higher cost at comparable resources; EU region availability is more constrained; the same
smaller-vendor risk without the pricing advantage.

## Decision

**Option D for compute: Fly.io, Frankfurt (`fra`).** Managed Postgres from a dedicated provider, not from the
compute platform (**OQ-INFRA-1** decides which). Object storage on R2 (ADR-0009). Static frontend on Cloudflare
Pages.

The vendor risk is deliberately bounded:

- Everything is a plain Docker image configured entirely from the environment.
- No Fly-specific API is called from application code.
- The database is managed and portable; storage is S3-compatible.
- Migration to ECS, Cloud Run, or a Hetzner box with Compose is a deployment-manifest change, not a rewrite.

EU residency is enforced by a CI check that parses the infrastructure config and fails on any non-EU region string
(`NFR-036`).

## Consequences

**Positive** — deploys are one command; the cost envelope fits with headroom; rolling deploys and health checks come
free; a single region keeps the mental model small enough to hold at 3 a.m.

**Negative** — dependency on a smaller vendor whose incidents we cannot influence; single region means a regional
outage is a full outage (accepted: offline clients keep capturing, which is the mitigation `NFR-025` describes);
platform metrics and audit tooling are thinner than a hyperscaler's.

**Neutral** — separating the database from the compute vendor adds a small amount of configuration and removes a
large amount of lock-in.

## Revisit when

A customer contract requires a specific hyperscaler or a formal availability SLA, a Fly incident materially breaches
`NFR-020`, or scale makes reserved-instance pricing elsewhere cheaper.
