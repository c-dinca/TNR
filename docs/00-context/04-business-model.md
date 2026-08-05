# Business model

Documented here because it constrains architecture: metering, reporting, and multi-org data isolation are
revenue-critical, not nice-to-have.

---

## 1. Value proposition, per audience

**To the NGO (the user):** stop losing field intelligence, stop driving empty kilometres, stop assembling grant
evidence by hand.

**To the foundation (the payer):** see, per euro, how many verifiable sterilisations occurred, where, and what
coverage they bought. Fund operations you can audit instead of operations you have to trust.

The second is what gets renewed. Everything the product does in the field must roll up into an auditable number.

## 2. Phase 1 revenue model

**B2B SaaS subscription, tiered by operational volume** — animals processed per year and vehicles coordinated.
Volume-based rather than seat-based, deliberately: NGOs run on unpaid volunteers, so per-seat pricing would cap
adoption exactly where we want it uncapped. The more volunteers an org onboards, the better our data moat and the
higher the tier they eventually reach through throughput.

Indicative tiers (to validate with the first three customers, not to be hard-coded):

| Tier | Fits | Limits | Notes |
|---|---|---|---|
| **Field** | Small local associations | 1 vehicle, ≤ 500 interventions/yr, 10 volunteers | Low price or free-with-attribution; a pipeline and data-coverage play |
| **Campaign** | Regional NGO running seasonal campaigns | ≤ 5 vehicles, ≤ 3,000 interventions/yr | Route optimisation, donor reporting, evidence packs |
| **Foundation** | Large international operators, mega-shelters | Unlimited vehicles, ≥ 3,000 interventions/yr | Multi-org rollups, grant-period reporting, SSO, data export, SLA |

Add-ons: extra evidence-pack signing, historical data import, custom donor report templates.

**Architectural consequence:** interventions, vehicles and active memberships must be countable per org per
period, cheaply and reliably, from day one. Metering is specified in
[`../02-architecture/08-audit-and-donor-reporting.md`](../02-architecture/08-audit-and-donor-reporting.md).
Enforcement of limits is deliberately *soft* in Phase 1 — we surface overage, we never block a field volunteer
mid-campaign because a counter tripped.

## 3. Who signs

Purchase almost never originates with the Romanian shelter. The realistic motion is:

1. Land a shelter coordinator as a champion (free trial, one campaign).
2. That coordinator's next grant application includes TNR-OS-generated evidence.
3. The foundation notices the reporting quality and either funds the licence as a line item in the grant, or
   mandates it across the operations it sponsors.

Selling the tool as a **grant line item** is the highest-leverage path: the foundation is already budgeting for
monitoring and verification, and we are cheaper and better than the status quo of manual reporting.

**Architectural consequence:** a foundation must be able to see across the orgs it funds without those orgs
seeing each other. This is the `grant` → `campaign` → `org` rollup, and it is why cross-org read scopes exist in
the permission model ([`../02-architecture/06-auth-and-tenancy.md`](../02-architecture/06-auth-and-tenancy.md))
rather than being bolted on later.

## 4. Unit economics envelope (Phase 1)

Solo founder, pre-revenue. The infrastructure budget target is **< €150/month** until the third paying customer.

| Line | Target |
|---|---|
| Managed Postgres + PostGIS (EU) | €25–50 |
| App + worker containers (Fly.io, fra) | €20–40 |
| Redis | €10 |
| Object storage + egress (R2, no egress fee) | €5–15 |
| Map tiles (self-hosted PMTiles on R2) | ~€0 |
| OSRM/VROOM routing container | €15–25 |
| Error tracking, uptime, logs (free tiers) | €0–20 |

This budget is the reason for several ADRs: self-hosted routing rather than a commercial matrix API (ADR-0011),
PMTiles rather than Mapbox (ADR-0007), and R2 for zero-egress media (ADR-0009). Media egress from photo-heavy
evidence packs is the most likely cost blow-out; media derivatives and signed short-lived URLs exist partly to
contain it.

Gross margin at the Campaign tier should exceed 85% once fixed infrastructure is amortised over three customers.

## 5. Phase 2 economics (context only)

The hardware phase sells the sensor **at or near manufacturing cost** and takes margin through a materially
higher recurring subscription covering M2M SIM data and premium alerting. Hardware is a moat, not a profit
centre; the recurring software revenue is the business.

This is why Phase 2 must not require a new platform: the sensor's value is the notification, and the
notification is delivered by Phase 1's infrastructure.

## 6. Defensibility

Ranked by durability:

1. **Data moat** — multi-year pack locations, sterilisation status and coverage history for Romanian
   localities. Cannot be bought or scraped, only accumulated.
2. **Workflow lock-in** — once campaign planning and donor reporting run on the platform, switching cost is a
   whole season.
3. **Donor-side credibility** — being the format foundations expect to receive evidence in.
4. **Hybrid bits-and-atoms** (Phase 2) — a competitor must displace both the software workflow and a deployed
   sensor fleet.

Note the ordering: none of the top three is technical. The code is the means; the data and the habit are the
asset. This is exactly why Phase 1 optimises for adoption friction (offline, Romanian, three-tap capture) over
feature breadth.

## 7. Risks to the model

| Risk | Mitigation in scope |
|---|---|
| NGOs have no budget authority | Sell through the grant; make evidence quality the wedge |
| A foundation builds it internally | Data moat + speed; foundations fund, they do not ship software |
| Legislative change collapses TNR funding | Coverage/impact data is valuable to any policy regime, including a humane-management mandate |
| Volunteers refuse a new tool | Three-tap capture, works offline, no login friction in the field, Romanian-first |
| Free-tier abuse / competitor recon | Soft limits plus per-org data isolation; precise geometry never leaves the owning org |
| Data misuse by a bad-faith org (culling contractor) | Terms of service prohibition, per-org access grants, no public pack API |
