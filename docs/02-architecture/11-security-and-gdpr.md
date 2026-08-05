# Security and GDPR

Requirements: `FR-120`–`FR-126`, `NFR-030`–`NFR-038`.

An unusual property of this product: the most sensitive data is not personal data. Precise stray-dog locations
are dangerous in their own right — published coordinates enable poisoning, and yard-dog sightings can identify a
household indirectly. The security model treats location as sensitive alongside PII.

---

## 1. Threat model

Assets, ranked by what their loss would cost:

| Asset | Impact if compromised |
|---|---|
| Precise pack/sighting locations | Animals poisoned or culled; the customer's trust is unrecoverable |
| Audit chain integrity | The entire donor-facing value proposition collapses |
| Evidence media | Fraud accusations; grant clawback |
| Volunteer PII (name, email, movement patterns) | Personal safety; GDPR exposure |
| Household references | Indirect identification of poor rural families |
| The aggregate data moat | Competitive loss; the main durable asset |
| Credentials | Everything above |

### 1.1 Adversaries

| Adversary | Motivation | Realistic capability |
|---|---|---|
| Opportunistic attacker | Automated scanning, credential stuffing | Low; commodity tooling |
| Capture-and-kill contractor | Wants pack locations to fulfil a municipal contract | Moderate; may pose as an NGO to get an account |
| Hostile individual | Ideologically anti-stray; wants to poison | Low technical, high motivation |
| Competitor | Wants the data moat | Moderate; may sign up for a trial |
| Malicious insider at a customer org | Data exfiltration, evidence forgery | High access within one org |
| Us (accidental) | Misconfiguration, logging a coordinate, a bad migration | **The most likely cause of an actual incident** |

The last row drives more design than the others: strict CSP, structural log redaction, EU-region CI checks, the
adversarial tenancy suite, and expand/contract migrations all exist primarily to protect against our own mistakes.

### 1.2 STRIDE summary

| Threat | Mitigation |
|---|---|
| **S**poofing | Argon2id, rotating refresh with family revocation, EdDSA-signed access tokens, per-account and per-IP backoff |
| **T**ampering | Hash-chained audit, append-only interventions, immutable media with server-verified hashes, DB role without `UPDATE`/`DELETE` on audit |
| **R**epudiation | Every mutation audited with actor, request id and IP hash in the same transaction |
| **I**nformation disclosure | Session-derived tenancy, adversarial CI suite, geometry omitted for funders, structural log redaction, short-lived signed media URLs |
| **D**enial of service | Cloudflare in front, per-identity rate limits, bounded batch sizes, queue isolation per org |
| **E**levation of privilege | Roles fixed at invitation issue and re-verified at acceptance, service-layer authorisation, no client-supplied `org_id` |

## 2. Application security controls

| Control | Implementation |
|---|---|
| Transport | TLS 1.2+, HSTS with preload, no mixed content (`NFR-031`) |
| CSP | No `unsafe-inline` for scripts; explicit connect/img/worker sources; service-worker scope explicit (`NFR-038`) |
| Other headers | `X-Content-Type-Options`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy` denying everything except geolocation |
| CORS | Explicit origin allowlist; no wildcard with credentials |
| Input validation | Zod at every boundary; unknown fields ignored, not echoed |
| Output encoding | React escaping; `dangerouslySetInnerHTML` banned by lint |
| SQL injection | Parameterised queries only; string-concatenated SQL banned by lint |
| Authorisation | Enforced in the service layer, not only in controllers (`AGENTS.md` §4) |
| Rate limiting | Per IP and per identity on auth, sync, presign, export (`NFR-035`) |
| Dependencies | Lockfile committed, `pnpm audit` in CI failing on critical/high (`NFR-033`), Dependabot weekly |
| Secrets | Environment only, schema-validated at boot, secret scanning in pre-commit and CI (`NFR-032`) |
| File uploads | MIME allowlist, magic-byte validation, size caps, no SVG (`FR-066`) |
| Session storage | IndexedDB rather than `localStorage`; access token in memory in console mode |

## 3. Data classification

| Class | Examples | Handling |
|---|---|---|
| **Critical** | Precise coordinates, audit chain, evidence media | Never logged, never exposed cross-org, never in a funder response, EU-only |
| **Sensitive personal** | User names, emails, IPs, volunteer movement patterns | Minimised, redacted from logs, DSR-exportable, retention-bounded |
| **Sensitive operational** | Costs, budgets, donor identities | Role-restricted (hidden from volunteers and vets) |
| **Internal** | Pack names, mission plans | Org-scoped |
| **Public** | Marketing copy, aggregate national statistics we choose to publish | Reviewed before release |

Note what is absent by design: no owner names, no phone numbers, no addresses. Yard dogs carry a
`household_ref` free label instead (`FR-057`). This is deliberate data minimisation — collecting rural owners'
identities would create a GDPR liability and, worse, a database that could be used against a population already
avoiding the authorities. §1 explains why we would rather not hold it at all.

## 4. GDPR

### 4.1 Roles

TNR-OS is the **processor** for customer operational data; each NGO is the **controller** of its org's data. For
our own user accounts and telemetry we are the controller. A Data Processing Agreement is a prerequisite for the
first paying customer (`TNR-119`).

### 4.2 Lawful basis

| Processing | Basis |
|---|---|
| User accounts, authentication | Contract (Art. 6(1)(b)) |
| Field operational data (sightings, packs, animals) | Legitimate interest (Art. 6(1)(f)) — animal welfare and public health; DPIA-documented |
| Evidence retention for donor audit | Legitimate interest, plus contractual obligation to the funder |
| Product telemetry | Legitimate interest, minimised and pseudonymised |
| Marketing email | Consent (Art. 6(1)(a)) |

Animal data is not personal data. It becomes personal-adjacent when it can identify a household, which is exactly
why `household_ref` is a free label, why owned-dog sightings are excluded from funder views, and why coordinates
are never logged.

### 4.3 Data subject rights

| Right | Implementation |
|---|---|
| Access / portability (Art. 15, 20) | `POST /v1/admin/dsr/export` → JSON + CSV of everything tied to the user (`FR-120`) |
| Erasure (Art. 17) | `POST /v1/admin/dsr/erase` — pseudonymises the user, retains anonymised operational records (`FR-121`) |
| Rectification (Art. 16) | Profile self-edit; operational corrections via the supersede mechanism |
| Restriction / objection | Membership deactivation, telemetry opt-out |
| Notification of a breach | 72-hour procedure in the incident runbook |

**Erasure semantics** — the interesting case. A volunteer who submitted 400 sightings and asks for erasure cannot
have those sightings deleted: they are part of an audit trail underpinning grants already disbursed, and a funder
has copies of reports counting them. So erasure:

```
- user row → email/name/phone replaced with a deterministic pseudonym; credentials destroyed; sessions revoked
- sightings/interventions → reported_by_user_id retained as the pseudonymous id, personal fields removed
- audit events → actor_user_id retained (chain integrity); no personal data was ever stored in the chain
- media uploaded_by → pseudonymous id
- a dsr.erasure_performed audit event records the legal basis for retention (`FR-121`, `FR-122`)
```

This is documented in the privacy policy before the first customer, not discovered during a request. The
pseudonymisation approach is also why the audit chain never contains a name or an email — only ids — so the chain
never has to be broken to satisfy a right to erasure. That constraint was designed in from the first schema.

### 4.4 Retention (`FR-123`)

| Class | Retention | Rationale |
|---|---|---|
| Sightings, packs, animals | Life of the org + 2 years | Coverage trend analysis needs multi-year history |
| Interventions and evidence | 10 years | Grant audit periods and veterinary record norms |
| Audit events | 10 years | Must outlive the records they describe |
| Media originals | 10 years (cold after 180 days) | Evidence |
| Access logs | 90 days | Security investigation |
| Telemetry | 13 months | Seasonality comparison |
| Deleted (soft) records | Purged 30 days after `deleted_at` | Reversibility window (`NFR-063`) |
| Idempotency records | 24 hours | Replay window |
| Invitations | 30 days after expiry | — |

A nightly `retention-sweep` enforces these and logs its actions. Periods are configurable per data class, because a
foundation's grant agreement may require longer than our default.

### 4.5 Records and assessments

- **Article 30 record of processing** (`FR-125`) maintained in `docs/compliance/ropa.md` (`TNR-119`).
- **DPIA** required before the first production customer, given large-scale location processing.
- **Sub-processors** listed publicly and kept current: hosting, managed database, object storage, email, error
  tracking. All EU-region or covered by an adequacy mechanism.

### 4.6 Data residency (`FR-124`, `NFR-036`)

Every data-holding service is EU-region. A CI check parses the infrastructure config and fails on any non-EU
region string. Error tracking and email are configured to EU endpoints. No customer data is processed outside the
EU, including in support workflows.

## 5. Terms-of-use restrictions

The security model has a non-technical component. Terms of service must prohibit use of TNR-OS data for capture
intended to end in euthanasia as a population-control measure, and prohibit redistribution of pack locations
outside the org.

This is enforced socially and contractually, not technically: an org with legitimate access to its own data can
misuse it. The technical mitigations are per-org isolation, no public API, no cross-org discovery, audit-logged and
rate-limited exports, and a manual review step before a new org is granted a paid tier. Stated plainly so nobody
mistakes the terms for a technical control.

## 6. Secure development practice

| Practice | Implementation |
|---|---|
| Secret scanning | Pre-commit hook plus CI (gitleaks) |
| Dependency scanning | `pnpm audit` in CI, failing on critical/high in production dependencies |
| SAST | ESLint security rules, `semgrep` on a security ruleset |
| Container scanning | Trivy on built images, failing on critical |
| The adversarial tenancy suite | Every route, every verb, cross-org attempts must fail (`NFR-030`) |
| Migration review | Any migration touching `audit_event` or `intervention` requires explicit justification in the PR |
| Least privilege | Separate DB roles for app, migration and analytics |

## 7. Incident response

```
1. Detect     — alert, customer report, or audit verification failure
2. Contain    — revoke credentials, disable the affected path, scale to zero if necessary
3. Assess     — what data, whose, how much; consult audit log and access logs
4. Notify     — controller (customer) without undue delay; supervisory authority within 72 h if required
5. Remediate  — fix, deploy, verify
6. Post-mortem — blameless write-up in docs/incidents/, with the specific prevention change
```

Special case — **audit chain failure**: treat as an integrity incident even if the cause is a bug. Preserve the
database state, identify the first broken sequence, determine whether any issued report covers the affected range,
and notify affected funders if a report's guarantee is compromised. Silence here would destroy the product's core
claim far more thoroughly than the bug itself.

## 8. Open questions

> **OQ-SEC-1** — Should MFA be mandatory for `owner`/`admin`? It is friction for a small NGO and protection for the
> account that can export everything. Leaning: optional at first, mandatory before the first Foundation-tier
> customer.

> **OQ-SEC-2** — Do we need field-level encryption for `household_ref`? Currently minimised to a free label with no
> personal data, which may be sufficient. Revisit if customers start putting names in it — and detect that with a
> heuristic check.

> **OQ-SEC-3** — Legal review of the terms-of-use prohibition on culling use: is it enforceable under Romanian law?
> Needs a lawyer before the first paid contract.
