# Authentication, authorisation and multi-tenancy

Requirements: `FR-001`–`FR-019`, `FR-030`–`FR-033`, `NFR-030`, `NFR-035`.

---

## 1. Model

Three concepts, kept strictly separate:

- **`user`** — a global identity with credentials.
- **`org`** — a tenant. All domain data belongs to exactly one.
- **`membership`** — the `(user, org, role)` link. **All permissions derive from here**, never from the user.

A user may hold memberships in several orgs (a vet contracting for two NGOs; a consultant advising three). The
active org is part of the access token, so every request is unambiguously scoped.

## 2. Authentication

### 2.1 Credentials

Argon2id password hashing (`memoryCost` 19 MiB, `timeCost` 2, `parallelism` 1 — the OWASP baseline), minimum 12
characters, checked against a common-password list (`FR-002`). Passwords never appear in logs, error reports or
audit diffs.

### 2.2 Tokens

| Token | Form | Lifetime | Storage |
|---|---|---|---|
| Access | JWT (EdDSA, Ed25519) | 15 min | Memory in console mode; IndexedDB in field mode |
| Refresh | Opaque 256-bit random | 90 days, rotating | IndexedDB, hashed at rest server-side |

Access token claims:

```json
{
  "sub": "<user_id>", "org": "<org_id>", "role": "coordinator",
  "perms": ["sighting:create", "pack:read", "..."],
  "jti": "<token_id>", "iat": ..., "exp": ...
}
```

Permissions are embedded so the API avoids a membership lookup per request, and the UI can hide what the user
cannot do. The cost is up to 15 minutes of staleness after a role change — accepted, and the reason role changes
write an audit event and why revocation-sensitive operations (funder access, membership deactivation) re-check the
database rather than trusting the claim.

EdDSA rather than RS256: smaller tokens, faster verification, no key-size footguns. Keys rotate via a JWKS-style
key set with an overlap window; `kid` is in the header from day one so rotation never requires a flag day.

### 2.3 Refresh rotation and reuse detection (`FR-004`)

Refresh tokens form a **family** per login. Each refresh issues a new token and marks the old one used. Presenting
an already-used token means either theft or a client bug, and we cannot distinguish them — so the entire family is
revoked, an audit event is written, and the user re-authenticates.

The 90-day lifetime is a deliberate product decision: a volunteer must never meet a login wall in a village with
no signal (`NFR-011`). It is compensated by rotation, family revocation, session listing (`FR-019`), and the fact
that field-mode tokens carry only field permissions.

### 2.4 Offline session validity

Field mode starts with no network if a valid session exists locally: the app reads the cached identity and
permission set from IndexedDB and enables capture immediately. It refreshes opportunistically when connectivity
returns. A `401` mid-drain triggers a refresh and, on failure, keeps everything queued and prompts for
re-login — **never** a logout that clears local data (`FR-006`).

### 2.5 Rate limiting and lockout

5 login attempts/min per IP, 10/hour per account, exponential backoff (`FR-008`). No hard account lockout: it is a
denial-of-service vector against exactly the volunteer we need in the field. Backoff plus alerting on
distributed attempts is the trade-off taken.

## 3. Roles and permissions

### 3.1 Roles (`FR-017`)

| Role | Intended holder | Scope |
|---|---|---|
| `owner` | NGO director / founder | Everything, including billing and org deletion |
| `admin` | Operations manager | Everything except org deletion and owner removal |
| `coordinator` | Ana — shelter coordinator | Full operational: packs, missions, vehicles, campaigns, reports |
| `vet` | Dr. Elena | Interventions, animals, own mission stops; no org admin, no financials |
| `volunteer` | Mihai | Create sightings, execute assigned missions; read only what is assigned |
| `funder` | Klaus — programme officer | Read-only reports and metrics for explicitly granted campaigns |

### 3.2 Permission matrix

`C` create · `R` read · `U` update · `D` soft delete · `—` none · `A` assigned-only · `Agg` aggregated only

| Resource | owner | admin | coordinator | vet | volunteer | funder |
|---|---|---|---|---|---|---|
| org settings | CRUD | RU | R | R | R | — |
| membership | CRUD | CRU | R | — | — | — |
| invitation | CRUD | CRUD | C R | — | — | — |
| sighting | CRUD | CRUD | CRUD | CR | **C** + R(own) | — |
| pack | CRUD | CRUD | CRUD | R | R (A) | Agg |
| pack precise geometry | R | R | R | R | R (A) | **—** |
| animal | CRUD | CRUD | CRUD | CRU | R (A) | — |
| intervention | CR + correct | CR + correct | CR + correct | **CR + correct** | — | Agg |
| vehicle | CRUD | CRUD | CRUD | R | R (A) | — |
| mission | CRUD | CRUD | CRUD | R (A) | R (A) | — |
| mission stop outcome | CU | CU | CU | **CU (A)** | **CU (A)** | — |
| campaign | CRUD | CRUD | CRU | R | — | R (granted) |
| grant / donor | CRUD | CRUD | R | — | — | R (own) |
| cost fields | CRUD | CRUD | CRU | — | — | Agg |
| report | CR | CR | CR | R | — | **R (granted)** |
| evidence pack | CR | CR | CR | R | — | R (granted) |
| audit log | R | R | R (own org) | R (own actions) | R (own actions) | — |
| media | CRUD | CRUD | CRUD | CRU | **C** + R(own) | R (in granted reports) |
| export (CSV/DSR) | C | C | — | C (RECS csv) | — | — |
| device (Phase 2) | CRUD | CRUD | R | — | — | — |

Notable deliberate choices:

- **A volunteer can create but not edit or delete a sighting.** Sightings are append-only observations; letting the
  observer rewrite one undermines the data's evidential value.
- **A vet can create and correct interventions but never delete one.** Nobody can; corrections supersede
  (`FR-093`).
- **A funder never sees precise geometry, volunteer identities, or another campaign.** Enforced by omitting fields
  from the response, not by nulling them (`FR-031`).
- **Cost data is hidden from volunteers and vets.** Salary and budget inference from campaign costs is a real
  social problem inside small NGOs.

### 3.3 Permission naming and enforcement

`<resource>:<action>` — `sighting:create`, `pack:merge`, `intervention:correct`, `report:generate`,
`member:invite`, `export:recs_csv`.

Enforcement happens in **two** layers:

1. A guard checks the coarse permission from the token before the handler runs.
2. The **service layer** re-checks contextual rules: assigned-only access, funder grants, last-owner protection,
   org membership state. This is the authoritative check (`AGENTS.md` §4) — workers have no HTTP guard, and they
   run the same services.

Every module declares its requirements in `<module>.permissions.ts`, so an agent adding an endpoint has an obvious
place to look and a review has an obvious place to check.

## 4. Tenancy enforcement

### 4.1 The rules

1. `org_id` comes **only** from the verified access token. A request body containing `org_id` is ignored, and a
   lint rule flags any `org_id` read from `body`/`query`/`params` (`FR-030`).
2. Every repository method takes `OrgContext` as its first parameter. There is no callable path to a tenant table
   without one — a repository function without it does not typecheck.
3. Every tenant query includes `org_id = $ctx.orgId AND deleted_at IS NULL`.
4. Cross-org reads return `404`, not `403`, so existence is never revealed (`FR-032`).
5. Workers run with an explicit `SystemContext` that names the org it is operating on; there is no ambient
   "superuser" context in domain code.

### 4.2 Verification

A generated adversarial test suite (`NFR-030`) enumerates every route in the OpenAPI spec and, for each, seeds two
orgs and asserts that org A's identity cannot read, update or delete org B's resource. **A new endpoint that is not
covered fails CI** — coverage of this suite is measured against the route list, so forgetting is not possible.

This is why application-layer scoping was chosen over RLS (ADR-0016): the assurance comes from an exhaustive,
readable test rather than from policy expressions that are hard to reason about and harder to debug in a worker
context.

### 4.3 Funder cross-org reads

A foundation may fund several orgs and must see across them without those orgs seeing each other
(`04-business-model.md` §3). Implementation:

```
funder membership → funder_campaign_grant rows → (campaign_id, org_id) pairs
Every funder query is scoped to that explicit pair set, never to a whole org.
Responses are aggregated: no precise geometry, no volunteer identity, no unrelated campaign.
```

Funder access is time-boxed (`expires_at`) and revocable; revocation takes effect within one access-token lifetime,
and funder-visible report endpoints re-check the grant in the database on every request rather than trusting the
token claim.

## 5. Invitations

```
1. admin/owner POSTs /v1/invitations { email, role }
2. Server creates a single-use token (32 bytes random, stored hashed), expiry ≤ 14 days (`FR-012`)
3. Email carries the raw token in a link
4. Acceptance: existing user → membership created with exactly the invited role;
   new user → registration then membership, in one transaction (`FR-013`)
5. Re-inviting an existing member: idempotent, role unchanged (`FR-014`)
6. Revocable before acceptance; expired tokens return 410
```

An invitation can never escalate: the role is fixed at issue time and re-verified at acceptance against the
inviter's authority at that moment. If the inviter's own role was reduced in the interim, an invitation for a
higher role fails.

## 6. Sessions and devices

`GET /v1/auth/sessions` lists active refresh-token families with device label (from `X-TNR-Client`), created time,
last-used time and coarse location (country from IP, never a precise location). `DELETE` revokes one.

Field devices are labelled so a coordinator can recognise a lost phone and revoke it. Revoking a session does not
delete local data on that device — we cannot reach it — which is why field tokens carry minimal permissions and
why field mode holds only assigned-scope data (`05-offline-first-and-sync.md` §5).

## 7. Deliberately deferred

| Deferred | Reason | Revisit |
|---|---|---|
| SSO / SAML / OIDC | No customer has an IdP at this scale | Foundation tier demand |
| MFA | Real friction for field volunteers; low current threat | Before handling any payment data, or on first customer request for admin accounts |
| Passkeys | Attractive for coordinators; device support in rural Romania is uneven | Phase 1.5 for console-only |
| Fine-grained per-record ACLs | Role + assignment covers every known case | Only with a concrete customer need |
| Service accounts / public API | No integrator demand yet; `device` credentials in Phase 2 are a narrower case | Phase 2 |

## 8. Threats and mitigations

| Threat | Mitigation |
|---|---|
| Stolen field device with a 90-day token | Session revocation, minimal field permissions, assigned-scope data only, no financial access |
| Refresh token theft | Rotation with family revocation on reuse, audit event, session list visibility |
| Cross-tenant data leak | Session-derived `org_id`, repository-level `OrgContext`, adversarial CI suite |
| Privilege escalation via invitation | Role fixed at issue, re-verified against inviter authority at acceptance |
| Funder scope creep | Explicit grant pairs, DB re-check per request, geometry fields omitted not nulled |
| Brute force | Per-IP and per-account backoff, no enumerable error messages (`FR-005`) |
| Insider export of the data moat | Exports restricted to admin/owner, audit-logged with row counts, rate-limited (`FR-033`) |
| XSS stealing session material | Strict CSP without `unsafe-inline`, IndexedDB rather than `localStorage`, no `dangerouslySetInnerHTML` |
