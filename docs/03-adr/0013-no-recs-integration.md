# ADR-0013: No RECS integration; maintain a parallel operational registry

- **Status**: Accepted
- **Date**: 2026-08-05
- **Affects**: animal model, chip lookup, RECS CSV export, product positioning

## Context

Romanian law requires every owned dog to be microchipped (ISO 11784/11785, 15 digits, `642` prefix for Romania),
vaccinated against rabies, and registered in **RECS** — a closed national database operated by the **CMV**.

Hard facts (`[../00-context/02-ecosystem-and-stakeholders.md](../00-context/02-ecosystem-and-stakeholders.md)` §2):

- Write access is restricted to authorised veterinarians.
- There is **no public REST API**. None is published or planned.
- Public read checking exists only through fragmented portals: RomPetID, Europetnet, PetMaxx.

The obvious product instinct — "integrate with the national registry" — is not available.

## Options considered



### Option A — Scrape or automate the RECS interface on a vet's behalf

**For:** Would genuinely eliminate the duplicate data entry vets complain about most.
**Against:** Almost certainly violates terms of use; requires holding a veterinarian's credentials, which is a
serious liability and probably a breach of her professional obligations; extremely brittle against a government
UI that changes without notice; and it would make us complicit in any data-quality problem in a legally
significant register. A regulator-facing scandal would end the company.

### Option B — Wait for an official API before building animal identity

**For:** Clean, correct, no parallel data.
**Against:** There is no timeline and no signal that one is coming. Waiting means no animal identity, no
sterilisation tracking, and therefore no coverage metrics — which is the entire donor-facing value proposition.

### Option C — Maintain a parallel operational registry, with best-effort read enrichment

Our own animal records, keyed by microchip where one exists. Read-only lookup against public portals as
non-authoritative enrichment. A clean CSV export that makes the vet's own legally required RECS entry mechanical.

**For:** Legal and safe; delivers the operational value (avoid re-trapping, prove coverage) without touching the
official register; reduces vet burden via export rather than automation; keeps an integration option open if CMV
ever opens an API.
**Against:** Two sources of truth exist in the world, and they can diverge; we must be scrupulously careful never
to imply legal registration; vets still do their own RECS entry.

## Decision

**Option C.**

Explicit rules:

1. TNR-OS animal records are an **operational** registry, never a legal one. No UI text may imply RECS
  registration has occurred.
2. Chip lookup is asynchronous, cached, rate-limited, non-blocking, and labelled unofficial (`FR-054`, `FR-055`).
3. Never scrape an authenticated area; never hold a veterinarian's RECS credentials; never write to RECS.
4. Reduce vet burden through the versioned RECS CSV export (`FR-056`) — transcription instead of investigation.
5. The animal model carries the fields a future submission would need. That is a preserved option, not a
  dependency.



## Consequences

**Positive** — no legal or professional-conduct exposure; the product ships without waiting on a government that
may never act; vets get real relief through export; the data moat is ours and grows independently.

**Negative** — vets still double-enter, so the pain is reduced rather than removed; our chip data may diverge from
RECS; we cannot claim national-registry integration in sales conversations where a competitor might imply it.

**Neutral** — if CMV opens an API, integration becomes a new ADR and most likely a vet-authenticated delegation
flow rather than a service credential.

## Revisit when

CMV publishes an API or a formal data-sharing programme, or a veterinary association approaches us about a
sanctioned channel.