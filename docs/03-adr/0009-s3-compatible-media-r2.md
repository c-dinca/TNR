# ADR-0009: S3-compatible object storage on Cloudflare R2

- **Status**: Accepted
- **Date**: 2026-08-05
- **Affects**: media pipeline, `infra/`, evidence packs

## Context

Media is the evidence that unlocks grants, and it is the most likely cost blow-out (`NFR-052`). Projected Phase 1
volume: up to 5 million objects (`NFR-051`), with evidence packs bundling thousands of photos for download by
funders. Requirements include EU residency (`FR-124`), versioning for recoverability (`NFR-024`), and presigned
direct upload so bytes never transit the API (`FR-060`).

Egress is the dominant variable: every evidence pack download and every funder review pulls media out.

## Options considered

### Option A — AWS S3 (eu-central-1)

**For:** The reference implementation; every feature, every tool, every SDK.
**Against:** Egress at roughly $0.09/GB. A handful of photo-heavy evidence packs per month can rival the entire
infrastructure budget. Also the most expensive storage per GB of the candidates.

### Option B — Backblaze B2

**For:** Very cheap storage; free egress via the Cloudflare Bandwidth Alliance.
**Against:** EU region is available but the account/region model is less clean; S3 compatibility is good but not
complete; the free-egress path depends on a partnership arrangement rather than a first-party guarantee.

### Option C — Provider-native storage (Fly Volumes / Tigris)

**For:** Co-located with the app, minimal latency.
**Against:** Ties durable evidence to the compute platform we deliberately treat as replaceable (ADR-0012). Losing
media is unrecoverable; it must not depend on the same vendor as the containers.

### Option D — Cloudflare R2 (EU jurisdiction)

**For:** **Zero egress fees** — the single most important property given evidence-pack downloads; S3-compatible
API so the SDK and presigning work unchanged; EU jurisdiction available; versioning and lifecycle rules; integrates
with the Cloudflare cache already fronting the app; also serves the PMTiles archive (ADR-0007).
**Against:** Fewer features than S3 (no cross-region replication, simpler IAM); a younger service; another
Cloudflare dependency alongside DNS/CDN/Pages.

## Decision

**Option D.** Cloudflare R2 with EU jurisdiction, accessed through the S3-compatible API.

Layout, lifecycle and integrity rules are in
[`../02-architecture/07-media-and-ml-pipeline.md`](../02-architecture/07-media-and-ml-pipeline.md) §3.
Direct presigned upload (`FR-060`), server-verified SHA-256 (`FR-061`), versioning for ≥ 30 days (`NFR-024`),
originals to infrequent access after 180 days.

Because the API is S3-compatible, MinIO serves as the local development equivalent, and migrating to S3 or another
provider is a configuration change.

## Consequences

**Positive** — evidence-pack downloads do not create a cost cliff; presigned uploads keep media bytes out of the
API; the same bucket infrastructure serves media, reports and map tiles; local development matches production
semantics via MinIO.

**Negative** — increased concentration on Cloudflare (DNS, CDN, Pages, R2), so a Cloudflare account-level incident
has a wide blast radius; R2's IAM is coarser than S3's; no cross-region replication, so the versioning and backup
story must be verified rather than assumed.

**Neutral** — S3 compatibility means this decision is genuinely reversible.

## Revisit when

Cloudflare concentration becomes an unacceptable single point of failure, or storage volume reaches a scale where
per-GB pricing differences outweigh egress savings. Measure both before switching.
