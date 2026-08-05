# Phase 1 scope and personas

## 1. One-sentence scope

**TNR-OS Phase 1 lets an NGO collect field sightings offline, curate them into packs, plan optimised capture
missions for its vehicles, record veterinary interventions with verifiable evidence, and generate donor-grade
impact reports.**

Anything that does not serve that sentence is out of scope for Phase 1.

## 2. In scope

| # | Capability | Why it is in |
|---|---|---|
| 1 | Org + user management, invitations, roles | Multi-tenant from day one; retrofitting tenancy is a rewrite |
| 2 | Offline-first sighting capture (PWA) with photos | The core data-acquisition loop; the whole data moat starts here |
| 3 | Pack clustering (automatic proposal + manual curation) | Turns raw pins into the planning unit |
| 4 | Animal records with microchip and ear-notch status | Prevents needless re-trapping; enables coverage maths |
| 5 | Mission planning with route optimisation | The fuel-and-time saving that makes the tool pay for itself |
| 6 | Mobile mission execution (stop-by-stop, offline) | Field reality: no signal mid-trip |
| 7 | Intervention recording | The billable, reportable, auditable unit |
| 8 | Hash-chained audit log | Donor trust; non-negotiable |
| 9 | Coverage and impact dashboards | The payer's screen |
| 10 | Evidence packs and campaign/grant reports (PDF + CSV) | The artefact that wins grants |
| 11 | Romanian + English localisation | Users are Romanian; payers are not |
| 12 | GDPR tooling (export, erasure, retention) | Legal precondition for EU operation |
| 13 | Microchip lookup enrichment (best effort) | Cheap value; must never block a write |

## 3. Out of scope for Phase 1

| Excluded | Reason | Revisit |
|---|---|---|
| IoT trap sensors | Software wedge sequencing; see triggers in the roadmap | Phase 2 |
| Ear-notch detection by ML | Needs a labelled corpus that only Phase 1 usage can produce | Phase 1.5 (`TNR-110`) |
| Public "report a stray" intake | Untrusted input poisons the data moat before it forms | Phase 1.5 (`TNR-115`) |
| Export/TRACES NT/CHED compliance | Regulatory hazard, separate product | Phase 3 |
| Municipal/B2G sales surfaces | Slow, politicised, trust-destroying with the NGO base | Not planned |
| Veterinary practice management, clinical records | Different product, crowded market | Not planned |
| Donation collection, adoption marketplace | Not our friction | Not planned |
| Native iOS/Android apps | PWA meets the need at a fraction of the cost | Only if push or BLE forces it (Phase 2) |
| RECS write integration | Legally impossible for third parties | Only if CMV opens an API |
| Billing/payments in-product | Three customers can be invoiced by hand | After ~10 customers |
| Real-time vehicle tracking | Privacy-sensitive with volunteers; low marginal value vs. cost | Evaluate in Phase 2 |

## 4. Personas

### 4.1 Ana — Shelter coordinator (primary buyer-champion)

| | |
|---|---|
| Age/context | 38, works at a regional NGO near Pitești, ex-office administrator |
| Device | Windows laptop, Chrome, 1366×768; Android phone |
| Connectivity | Office broadband; unreliable when travelling |
| Digital literacy | Comfortable with Excel and Facebook; not with "apps" |
| Time budget | 20 minutes each morning to plan the day; that is the whole window |
| Success | Every vehicle leaves with a printed/downloadable stop list, no two teams sent to the same village |
| Fears | Losing data she typed; being blamed for a wasted trip; a donor asking a question she cannot answer |
| Kills adoption | Anything that requires her to re-enter data she already has in Excel, or that loses a day's work |

Ana lives in the **dashboard**. She needs: map of packs, unassigned sightings queue, mission builder, today's
status, one-click report.

### 4.2 Mihai — Field volunteer (primary user by volume)

| | |
|---|---|
| Age/context | 24, volunteers weekends, drives his own car to villages |
| Device | €150 Android, 4 GB RAM, low free storage, cracked screen |
| Connectivity | 2G/EDGE in villages, frequently none; battery anxiety is real |
| Digital literacy | Fluent with phone, impatient with forms |
| Conditions | Cold, gloves on, one hand holding a leash or a phone torch |
| Success | Drop a sighting in under 15 seconds and know it will not be lost |
| Fears | "Did it save?"; using up his data allowance; a form that loses input when the signal drops |
| Kills adoption | A login wall in the field, a spinner, a required field he cannot answer, silent upload failure |

Mihai lives in the **capture flow**. He needs: a big button, GPS auto-filled, count, photo, done. Plus a visible,
trustworthy "3 pending, will send when online" indicator.

### 4.3 Dr. Elena — Veterinarian (secondary user)

| | |
|---|---|
| Age/context | 45, runs a small clinic, contracts with the NGO for campaign days |
| Device | Clinic desktop; Android tablet in the mobile clinic |
| Connectivity | Clinic Wi-Fi; nothing in the mobile unit |
| Constraint | 20–40 sterilisations on a campaign day; every second of admin is a second not operating |
| Legal duty | Must enter RECS herself; TNR-OS never claims to do it for her |
| Success | Log an intervention in under 60 seconds, then export the day's list for RECS entry |
| Kills adoption | Duplicate data entry, a form that demands fields she does not have mid-surgery |

Elena lives in the **intervention flow** and the **day export**.

### 4.4 Klaus — Foundation programme officer (the payer)

| | |
|---|---|
| Context | Manages a grant portfolio at a German/Swiss foundation |
| Device | Laptop, good connectivity, reads PDFs on a train |
| Language | German/English; no Romanian |
| Need | Verifiable numbers per grant period: interventions, cost per intervention, coverage change, geography |
| Success | Approve or renew funding without a phone call, and defend it to his board |
| Fears | Funding unverifiable activity; a scandal about mistreated animals or invented numbers |
| Kills renewal | Numbers he cannot trace to evidence |

Klaus lives in **reports and evidence packs**. He may never log in — the PDF may be his only contact with the
product, and it must be excellent.

### 4.5 Non-persona: the rural dog owner

Deliberately not a Phase 1 user. Reached only through Ana's household consent records. Any future surface for
this group must be framed as help offered, never registration or enforcement — see
[`02-ecosystem-and-stakeholders.md`](../00-context/02-ecosystem-and-stakeholders.md) §1.

## 5. Persona → surface matrix

| Surface | Ana | Mihai | Elena | Klaus |
|---|---|---|---|---|
| Mobile capture PWA | occasional | **primary** | — | — |
| Mission execution (mobile) | — | **primary** | occasional | — |
| Intervention form (mobile/tablet) | occasional | — | **primary** | — |
| Coordinator dashboard (desktop) | **primary** | — | — | rare |
| Reports & evidence packs | produces | — | — | **consumes** |
| Org & user admin | **primary** | — | — | — |

Two distinct front-end experiences share one codebase: a **field mode** optimised for offline, gloves and speed,
and a **console mode** optimised for map density and bulk operations. This is a routing and layout split, not two
apps — see [`../02-architecture/01-system-overview.md`](../02-architecture/01-system-overview.md).

## 6. The three loops that must work

Everything else is supporting cast.

**Loop 1 — Intelligence.** Mihai sees dogs → drops a sighting offline → it syncs → the system proposes a pack →
Ana confirms. *Measured by: sightings per active volunteer per week; median sync latency.*

**Loop 2 — Operations.** Ana selects packs → generates an optimised mission → assigns a vehicle → Mihai executes
stop by stop offline → outcomes recorded. *Measured by: planned vs. actual km; stops completed per mission.*

**Loop 3 — Proof.** Elena records interventions with photo evidence → the audit chain seals them → Ana generates
a grant report → Klaus funds the next campaign. *Measured by: interventions with complete evidence; time to
produce a report.*

If a proposed feature does not tighten one of these loops, it waits.
