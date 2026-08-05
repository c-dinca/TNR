# Glossary — binding vocabulary

This vocabulary is **normative**. The terms below are the names used in code identifiers, database tables, API
paths, TypeScript types, and English UI copy. Synonyms are listed so you can recognise them in conversation and
then *not* use them in the system.

Romanian UI strings are separate: they are translations of these concepts, defined in the i18n catalogue, and
never a second source of truth.

---

## Domain entities

### `org` (organisation)
The tenant. An NGO, foundation, or veterinary practice with its own users, vehicles and data. All domain data is
scoped to exactly one org. **Do not** call this a tenant, account, client, or shelter in code.

### `user`
A person with credentials. A user may belong to multiple orgs through a `membership`, which carries the role.

### `membership`
The `(user, org, role)` link. Permissions derive from it, never from the user directly.

### `sighting`
A single observation, at a point in time and space, that animals were present. Immutable after creation apart
from moderation fields. Created by a volunteer in the field (Phase 1) or by a trap device (Phase 2). **Not** a
report, ping, or observation.

Key attributes: location, `occurred_at`, estimated count, health notes, photos, reporter.

### `pack`
A persistent cluster of animals believed to live and breed together in one area. Derived from sightings, then
curated by a coordinator (merge, split, rename, mark resolved). This is the unit that campaigns target and the
unit against which coverage is measured. **Not** a colony, group, or herd.

### `animal`
An individual dog (the model does not preclude cats, but Phase 1 is dogs). May be identified by microchip,
ear-notch, or description only. Belongs to at most one pack at a time; keeps its identity if it moves.

### `ear notch` / `notched`
A small surgical cut in the ear indicating the animal has already been sterilised. The single most valuable
signal in the field, because it prevents needless re-trapping. Stored as an animal attribute and as a
per-sighting observation, since field observation is fallible.

### `intervention`
A recorded veterinary or handling act on one animal: sterilisation, rabies vaccination, microchip implantation,
treatment, or (as an attested medical decision only) euthanasia. **This is the billable, reportable, auditable
unit of the whole product.** Interventions are append-only; corrections are new records that supersede, never
edits. **Not** a surgery, procedure, or treatment in code.

### `mission`
A planned field operation for one date, one vehicle and one team: a set of stops, in an order, with an objective.
The output of route optimisation. **Not** a route, trip, or job.

### `stop`
One location within a mission — usually a pack location, sometimes a clinic, fuel point or handover. Ordered,
with an estimated arrival and a completion outcome.

### `vehicle`
A van, car or mobile clinic that missions are assigned to. Carries capacity attributes (cage slots) that
constrain route planning.

### `campaign`
A funded programme with a time window, a geographic scope, a target intervention count and a budget. Missions
and interventions roll up into a campaign; campaigns roll up into donor reports.

### `grant` / `donor`
The funding entity and the funding instrument. Present in Phase 1 only as far as reporting requires: a campaign
can belong to a grant, and a grant has a reporting period and a required metric set.

### `evidence pack`
A generated, signed archive (PDF summary + media manifest + hashes) proving that a set of interventions
occurred. The artefact NGOs hand to foundations.

### `device`
A Phase 2 IoT trap sensor. Modelled minimally in Phase 1 so that identity and event ingest exist as seams. Not
implemented as a product surface in Phase 1.

## Process terms

### TNR — Trap–Neuter–Return
Romanian: *CSR — Capturare–Sterilizare–Redare*. Trap the animal, sterilise it, return it to its territory. The
approach the product exists to industrialise.

### CNR — Catch–Neuter–Release
Synonym encountered in literature. Use **TNR**.

### `capture`
The act of an animal entering custody, whether by trap, hand, or net. In Phase 2 this becomes an event a device
can emit.

### `release` / `return`
Returning a sterilised animal to its original territory. Use **`release`** in code; "return" is reserved for its
programming meaning.

### `coverage`
Proportion of the estimated animal population in a geographic unit that has received a sterilisation
intervention. The headline outcome metric; a campaign's purpose is to push a locality above the epidemiological
threshold.

### `sterilisation rate`
Interventions of type `sterilisation` per unit time. An activity metric, not an outcome metric. Do not conflate
with coverage in reports.

## Institutions and systems

| Term | Meaning |
|---|---|
| **RECS** | *Registrul de Evidență a Câinilor cu Stăpân* — the closed Romanian national register of owned dogs. Write access: authorised vets only. No public API |
| **CMV** | *Colegiul Medicilor Veterinari* — the College of Veterinary Physicians; operates RECS |
| **ANSVSA** | The national sanitary-veterinary authority; sets veterinary rules |
| **RomPetID / Europetnet / PetMaxx** | Fragmented public microchip *lookup* portals. Read-only, best effort |
| **TRACES NT** | EU system for animal movement certification; issues CHED documents. Out of Phase 1 scope |
| **CHED** | Common Health Entry Document, required for cross-border animal movement |
| **Law 258/2013** | Romanian law permitting euthanasia of unclaimed strays after 14 working days |
| **`maidanez`** | Romanian colloquial term for a stray dog. Acceptable in Romanian UI copy; never an identifier |
| **`câine de curte`** | Yard dog — owned, free-roaming, usually unsterilised. The dominant source of new litters |
| **Smeura** | The world's largest dog shelter, in Pitești, Romania; >6,000 dogs. Design reference for scale |

## Technical terms used with a specific local meaning

| Term | Meaning here |
|---|---|
| **outbox** | The client-side queue of mutations made while offline, replayed on reconnect (ADR-0006) |
| **idempotency key** | Client-generated key making a replayed mutation safe. Mandatory on all mutating endpoints |
| **UUIDv7** | Time-ordered UUID. All primary keys. Generated client-side so offline records have final identity immediately (ADR-0005) |
| **problem document** | RFC 9457 `application/problem+json` error body. The only error shape the API returns |
| **audit event** | An entry in the hash-chained audit log. Written in the same transaction as the change it describes |
| **soft delete** | `deleted_at` timestamp. Domain records are never hard-deleted except through GDPR erasure |
| **data moat** | The accumulated, hard-to-replicate corpus of pack locations, sterilisation status and coverage history that makes the product defensible |
| **software wedge** | The strategy: enter with pure software, add hardware only after the software is load-bearing |

## Banned synonyms

Using these in code, schema or API is a review rejection:

| Do not use | Use |
|---|---|
| `tenant`, `account`, `shelter` (as tenant) | `org` |
| `report`, `ping`, `observation` | `sighting` |
| `colony`, `group` | `pack` |
| `dog` (as an entity) | `animal` |
| `surgery`, `procedure`, `treatment` (as an entity) | `intervention` |
| `route`, `trip`, `job` (as the planned operation) | `mission` |
| `waypoint`, `point` (as a mission element) | `stop` |
| `user_org`, `org_user`, `team_member` | `membership` |
