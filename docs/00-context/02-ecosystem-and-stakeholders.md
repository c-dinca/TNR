# Ecosystem, stakeholders and constraints

Executing a software wedge in Romania requires precise knowledge of who does what, what the law demands, and
where the data actually lives. This document is the reference for those facts. Product and architecture
decisions cite it.

---

## 1. Legal frame

### Mandatory identification

Every owned dog in Romania must be:

- **microchipped** with an ISO 11784/11785 transponder,
- **vaccinated against rabies**,
- **registered** in the national database.

Transponder characteristics that matter to us as input validation:

| Property | Value |
|---|---|
| Standard | ISO 11784 / ISO 11785 |
| Frequency | 134.2 kHz |
| Digits | 15, numeric |
| Romanian country prefix | `642` |

A chip read in Romania that does not begin with `642` is legitimate — it may be a foreign-registered animal —
so the UI must accept it while flagging it as non-Romanian. See `FR-052`.

### Mandatory sterilisation

Sterilisation is legally required for all dogs that are not a recognised pure breed (i.e. common and crossbred
dogs). This is the legal hook that makes TNR campaigns not merely tolerated but aligned with statute — useful in
grant narratives and in municipal negotiations.

### Penalties and the perverse incentive

Non-compliance carries fines of **2,000–5,000 RON** (roughly €400–1,000). For a rural household this is
catastrophic money. The practical result is the opposite of what the law intends: owners avoid contact with the
system entirely, do not present animals for chipping, and abandon them instead. Any product surface that looks
like enforcement will be avoided by exactly the population we need to reach. **TNR-OS must never present itself
to a rural citizen as an enforcement or reporting tool.**

## 2. The data bottleneck: RECS

Legal registration happens exclusively in the **RECS** — *Registrul de Evidență a Câinilor cu Stăpân* (Register
of Owned Dogs) — a closed national database operated by the **CMV** (*Colegiul Medicilor Veterinari*, the
College of Veterinary Physicians).

Hard constraints:

- **Write access is restricted to authorised veterinarians.** No third-party software may create or modify RECS records.
- **There is no public REST API.** The government publishes none. There is no sanctioned machine-readable interface.
- Public *read* checking exists only through fragmented lookup portals — **RomPetID**, **Europetnet**, **PetMaxx** — which answer "is this chip number registered, and with whom (partially)".

Consequences for our architecture:

1. TNR-OS maintains its **own** animal identity records, keyed by microchip number where one exists. It is a
   parallel operational registry, not a mirror of RECS, and the UI must never imply legal registration has occurred.
2. Chip lookup is a **best-effort enrichment**, implemented as an adapter with strict rate limiting, caching and
   graceful degradation. It is never on a critical write path. See
   [`../02-architecture/13-integrations.md`](../02-architecture/13-integrations.md) and ADR-0013.
3. Veterinarians will continue double-entering data into RECS. We reduce their burden by making *our* capture
   fast and by producing a clean, ordered work list and export — not by integrating with RECS.
4. If the CMV ever opens an API, our animal model already carries the fields needed to submit. That is a
   deliberate option, not a dependency.

## 3. Stakeholder matrix

The Phase 1 product targets front-line operational workflow. The matrix below maps each group's role, the
software gap we can close now, and the physical gap that motivates Phase 2 hardware.

### 3.1 NGOs — **primary Phase 1 user**

| | |
|---|---|
| **Role** | Rescue, rehabilitation, funding and execution of sterilisation campaigns, mega-shelter operation (e.g. Smeura, the world's largest shelter, >6,000 dogs) |
| **Digital gap** | Obsolete or absent mapping for capture campaigns; inability to prove clinical ROI to international donors; chaotic document management |
| **Physical gap** | Overcrowded shelter infrastructure; enormous logistics cost from empty vehicle runs during manual trapping in remote villages |
| **Phase 1 value** | Field intelligence centralised, duplicate effort prevented, mobile-clinic fuel optimised, cryptographically verifiable audit trail (geotagged, timestamped surgery photos) that unlocks institutional grants |

Named organisations operating in this space and relevant as design references or prospects: NetAP, Four Paws,
Tierhilfe Hoffnung.

### 3.2 Rural citizens

| | |
|---|---|
| **Role** | Owners of yard dogs, usually free-roaming; endemic poverty prevents compliance with chipping and sterilisation duties |
| **Digital gap** | No access to micro-funding that could subsidise mandatory veterinary fees; no information about mobile campaign visits |
| **Physical gap** | Cannot physically travel to urban veterinary clinics; unwanted litters abandoned in fields and forests |
| **Phase 1 posture** | **Not a user.** Reached indirectly: the NGO coordinator can see which households consented to sterilisation and when a clinic will visit. Direct citizen-facing surfaces are Phase 1.5 at the earliest (`TNR-115`), and must be framed as *help offered*, never as registration or enforcement |

### 3.3 Veterinarians

| | |
|---|---|
| **Role** | Perform the legally recognised acts — sterilisation, rabies vaccination, ISO 11784/11785 chip implantation — and enter the data manually |
| **Digital gap** | Redundant, tedious data entry into the archaic RECS interface and into EU pet-passport systems |
| **Physical gap** | Small-town clinics lack physical capacity to house dogs during post-operative recovery |
| **Phase 1 value** | A structured surgery list for the day, mobile-friendly intervention capture (chip, procedure, outcome, photo) in under 60 seconds per animal, and an export that makes their subsequent RECS entry mechanical rather than investigative |

Veterinarians are a **secondary user** in Phase 1: they log interventions inside an NGO's organisation, they are
not customers themselves.

### 3.4 International transporters

| | |
|---|---|
| **Role** | Export adopted dogs to Western Europe — the system's main relief valve |
| **Digital gap** | Overwhelming customs and sanitary compliance, especially CHED certificate generation via the EU **TRACES NT** system |
| **Physical gap** | Maintaining welfare standards (temperature, humidity, mandatory rest stops) across multi-thousand-kilometre transits |
| **Phase 1 posture** | **Out of scope.** High-value, high-complexity, and regulatorily hazardous. Deliberately deferred; the animal and document models are shaped so a future export-compliance module can attach without migration pain. See ADR-0014 |

### 3.5 Municipalities and public shelters

Legally central, commercially poisonous in Phase 1. They are the buyers of capture-and-kill services, procurement
is slow and politicised, and selling to them risks the trust of the NGO base. **Excluded from Phase 1 by
strategy, not by capability.**

## 4. Where the value concentrates

Reading the matrix: **export adoption** and **mass sterilisation campaigns** are the only two viable levers for
reducing the stray population without euthanasia. Both are severely friction-bound. Export is
regulation-heavy and slower to enter safely; sterilisation logistics is pure operations, and operations is what
software eats first.

**Phase 1 therefore attacks sterilisation campaign logistics for NGOs, and nothing else.**

## 5. Who uses versus who pays

| | |
|---|---|
| **Users** | Romanian shelter coordinators and local volunteers |
| **Payers** | Large international foundations (Switzerland, Germany, UK) that sponsor the operations |

This split shapes the product more than any technical constraint. The people typing into the app are not the
people writing the cheque. It follows that:

- The Romanian-facing UX must be brutally simple, work on cheap Android phones on 2G, and be fully localised in
  Romanian (`NFR-021`).
- The foundation-facing UX is fundamentally **reporting**: verifiable impact numbers, cost per intervention,
  coverage maps, exportable evidence packs — in English or German (`FR-070`–`FR-078`).
- Both live in one product. Neglecting the donor-facing half means the product never gets paid for; neglecting
  the field half means it never gets used.

Pricing consequences are in [`04-business-model.md`](04-business-model.md).

## 6. Environmental constraints that drive engineering

| Constraint | Engineering consequence |
|---|---|
| Villages with 2G, EDGE, or no coverage | Offline-first PWA, outbox sync, deferred media upload (ADR-0006) |
| Cheap Android devices, small storage | Client bundle budget, aggressive image downscaling on-device (`NFR-004`) |
| Volunteers with low digital literacy, wearing gloves, in the cold | Large touch targets, three-tap sighting capture, no nested navigation |
| Vehicles hundreds of km from base | Route data must be usable after cache load; no live-connection assumption during a trip |
| Donor audit demands | Immutable append-only intervention evidence, hash-chained audit log |
| GDPR, EU data residency | EU-only hosting and storage regions, DSR tooling from day one (ADR-0012) |
