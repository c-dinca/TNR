# ADR-0008: Own authentication with JWT access and rotating refresh tokens

- **Status**: Accepted
- **Date**: 2026-08-05
- **Affects**: `apps/api` auth module, `apps/web`

## Context

An unusual constraint drives this: a volunteer must **never** meet a login wall in a village with no signal
(`NFR-011`). That means a 90-day offline-valid session and an app that boots into full capture mode with no
network. Combined with multi-org memberships (`FR-009`) and per-org roles, the requirements do not match a
typical SaaS auth flow.

## Options considered

### Option A — Auth0 / Clerk / WorkOS

**For:** Battle-tested, MFA and SSO included, fast to integrate, someone else owns credential security.
**Against:** Per-MAU pricing against a user base of unpaid volunteers we actively want to grow — the pricing model
is inverted relative to our business model (`04-business-model.md` §2). Offline session semantics are not
something a hosted provider is designed for; long-lived refresh tokens with our rotation rules would fight the
product. Multi-org role modelling still has to live in our database anyway. Plus a hard dependency and EU-residency
questions on the login path.

### Option B — Supabase Auth

**For:** Cheap, includes refresh rotation, EU region available.
**Against:** Pulls in the wider Supabase platform or leaves an odd partial dependency; the same offline-session
mismatch; our authorisation model is custom regardless.

### Option C — Keycloak, self-hosted

**For:** Full control, standards-compliant, no per-user cost.
**Against:** A JVM service to operate, patch and back up — a large operational addition for one person, for a
feature we can implement in a few hundred well-tested lines.

### Option D — Own implementation

Argon2id passwords, EdDSA-signed JWT access tokens, opaque rotating refresh tokens with family revocation on reuse.

**For:** Exactly the semantics the field requires; no per-user cost; multi-org switching is a token mint; offline
boot is trivial because we control storage; no third party on the login path.
**Against:** We own credential security, and a mistake here is severe. No MFA or SSO out of the box. Password
reset, rate limiting, session listing and rotation all have to be built and tested.

## Decision

**Option D.** Own authentication, as specified in
[`../02-architecture/06-auth-and-tenancy.md`](../02-architecture/06-auth-and-tenancy.md).

The scope is deliberately narrow and well-trodden: Argon2id at OWASP parameters, 15-minute EdDSA access tokens,
90-day rotating opaque refresh tokens with family revocation, per-IP and per-account backoff without hard lockout,
and revocable session listing.

MFA and SSO are deferred (`06-auth-and-tenancy.md` §7), not refused.

## Consequences

**Positive** — 90-day offline sessions work exactly as the field needs; no per-MAU cost as volunteer numbers grow;
org switching and role changes are ours to control; no third-party dependency on the login path.

**Negative** — credential security is our liability; MFA and SSO must be built when demanded; this code needs
disproportionate test coverage and review; a token-handling bug is a serious incident, so the auth module carries
a mandatory second-look rule in review.

**Neutral** — moving to a provider later is possible but would require migrating password hashes (Argon2id is
portable) and reworking the offline session model, which is the part a provider would not support.

## Revisit when

A Foundation-tier customer requires SSO, or MFA becomes mandatory for admin accounts and building it ourselves
exceeds the cost of a provider for the console-only surface. A hybrid — provider for console, own tokens for
field — is a plausible future shape.
