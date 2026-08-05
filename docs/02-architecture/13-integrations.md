# External integrations

Every integration follows the same three rules:

1. **Behind an interface** in the domain layer, with a fake for tests.
2. **A documented degraded mode** — no third-party outage may block sighting capture, sync, or intervention
   recording (`NFR-016`).
3. **Never on a critical write path** unless there is genuinely no alternative.

---

## 1. Microchip registry lookup

### 1.1 Reality

There is no sanctioned API. Legal registration lives in **RECS**, a closed national database run by the **CMV**,
writable only by authorised veterinarians, with no public REST interface
([`../00-context/02-ecosystem-and-stakeholders.md`](../00-context/02-ecosystem-and-stakeholders.md) §2).

What exists is fragmented public *lookup* portals — **RomPetID**, **Europetnet**, **PetMaxx** — which answer "is
this 15-digit number registered somewhere, and roughly with whom".

### 1.2 What we do

Best-effort enrichment only (`FR-054`, `FR-055`):

```ts
interface ChipRegistryLookup {
  lookup(chip: string): Promise<{
    provider: 'rompetid' | 'europetnet' | 'petmaxx';
    found: boolean | 'unknown';
    registeredCountry?: string;
    registryName?: string;
    rawResponse: unknown;   // retained for audit
    checkedAt: string;
  }>;
}
```

| Property | Value |
|---|---|
| Invocation | Asynchronous job only. Never inside a request |
| Cache | 30 days per chip number; a registration rarely changes |
| Rate limit | 30/hour per org plus a global provider cap; sequential, never parallel |
| Failure | Result is `unknown`. The animal saves regardless |
| Presentation | Labelled unofficial and non-authoritative, with the provider and check time |
| Provider order | RomPetID → Europetnet → PetMaxx, stopping at the first definite answer |

### 1.3 Constraints and ethics

These portals are courtesy services for pet owners, not commercial APIs. We must not hammer them: strict rate
limits, generous caching, a real User-Agent identifying TNR-OS with contact details, and immediate honouring of any
request to stop. If a provider offers a formal agreement, take it. `CHIP_LOOKUP_ENABLED=false` disables the whole
integration by configuration, and it must remain a feature the product works fine without.

**No scraping of authentication-protected areas. No attempt to write to RECS. No implication in the UI that
registration has occurred.** A veterinarian's legal RECS entry remains her own act; we make it mechanical
(`FR-056`) rather than automated.

### 1.4 If CMV ever opens an API

The animal model already carries the fields a submission would need. That is a deliberately preserved option, not a
dependency. Any such integration would be a new ADR and, most likely, a vet-authenticated delegation flow rather
than a service credential.

## 2. RECS CSV export

Not an API integration — a **workflow reduction** (`FR-056`, `US-E4`).

Elena must enter each animal into RECS herself. Today she works from memory and paper. We give her a date-ranged
CSV in the column order the RECS form expects, so her data entry becomes transcription rather than investigation.

```
Columns: microchip, species, breed, sex, birth_year, colour, name,
         implant_date, implant_vet, rabies_vaccine_date, rabies_vaccine_batch,
         sterilisation_date, sterilisation_vet, owner_reference, locality, notes
```

The exact column set must be verified against the current RECS form before `TNR-088` and re-verified whenever a
customer reports a mismatch. It is a government form; it will change without notice, and the export is versioned
(`recs_csv_v1`) so a change does not silently corrupt a vet's workflow.

Exports are audit-logged with row counts (`FR-104`) and restricted by role.

## 3. Routing engine (OSRM + VROOM)

Self-hosted, both in one container (ADR-0011, [`04-geospatial-and-routing.md`](04-geospatial-and-routing.md) §4).

| Aspect | Detail |
|---|---|
| OSRM | `/table/v1/driving` for the duration/distance matrix |
| VROOM | Capacitated ordering with time windows |
| Data | Pinned Romania OSM extract, graph baked into the image at build time |
| Refresh | Quarterly, deliberate, tracked (`TNR-020`) |
| Degraded mode | Nearest-neighbour over great-circle distance, labelled `fallback_straight_line` (`FR-075`) |
| Cache | Pairwise matrix cached in Redis by rounded coordinate pair, 30-day TTL |

Self-hosting rather than a commercial matrix API: a 25-stop matrix is 625 elements, re-optimisation is frequent,
and per-element pricing would become a top cost line for zero functional gain (`NFR-053`). The cost is operating
one more container and owning the graph refresh.

## 4. Map tiles (PMTiles)

Self-hosted vector basemap (ADR-0007). A Romania extract as a single PMTiles archive in R2; MapLibre range-requests
it directly, fronted by the Cloudflare cache.

| Aspect | Detail |
|---|---|
| Source | OpenStreetMap-derived vector tiles, zooms 0–14 |
| Attribution | **Mandatory** OSM attribution in every map view and in every report map |
| Degraded mode | Cached tiles, then an explicit hatched "no map data" state — never blank white |
| Offline | Bounded region caching, default 150 MB (`FR-029`, `NFR-005`) |
| Cost | Storage plus cached range requests; no per-request fee |

Rejected: Mapbox and Google Maps — per-load pricing on a map-centric product with a €150/month budget, plus terms
that complicate offline caching, which is a hard requirement here rather than a nicety.

## 5. Transactional email

| Aspect | Detail |
|---|---|
| Uses | Invitations, password reset, report-ready notifications, security alerts |
| Provider | EU-region provider with an API (Postmark EU, Scaleway TEM, or SMTP) |
| Interface | `EmailSender` with a local fake writing to disk in development |
| Degraded mode | Queued with retry. No core flow blocks on email |
| Content rules | No PII beyond the recipient's own name; no signed media URLs; no coordinates |
| Deliverability | SPF, DKIM, DMARC configured before the first customer |

Invitation and reset links are single-use, short-lived tokens (`FR-007`, `FR-012`). Report links are signed and
short-lived — an email is forwardable, and an evidence pack must not become world-readable because someone
forwarded a notification.

## 6. Error tracking and telemetry

Sentry (or equivalent) with an EU data region (`FR-124`). PII scrubbing in `beforeSend` mirrors the logger's
structural redaction ([`10-observability-and-slos.md`](10-observability-and-slos.md) §5). Listed as a sub-processor
in the GDPR documentation.

## 7. Reference data

| Data | Source | Use | Notes |
|---|---|---|---|
| Romanian localities with SIRUTA codes | Open data / OSM administrative relations | Coverage aggregation, funder-visible geography | Licence and provenance unresolved — **OQ-GEO-1** |
| Locality population estimates | National statistics | Coverage denominator | Provenance must be displayed with every coverage figure |
| Dog population estimates per locality | **Unknown** | Coverage denominator | **OQ-DM-3**, blocks `TNR-095` |
| OSM road network | Geofabrik Romania extract | Routing | Pinned version, quarterly refresh |
| Common-password list | Public breach corpus | Password policy (`FR-002`) | Bundled, not fetched at runtime |

Reference data is loaded by seed scripts with a recorded source and version, never fetched live at runtime. A
coverage number whose denominator changed silently overnight is worse than no coverage number.

## 8. Deliberately not integrated in Phase 1

| System | Why not | Revisit |
|---|---|---|
| **TRACES NT / CHED** | EU animal-movement certification for export adoption. High value, high regulatory hazard, entirely separate workflow | Phase 3, own ADR |
| **EU pet passport systems** | Vet-authenticated, no third-party access | If a formal channel appears |
| **Payment processing** | Manual invoicing until ~10 customers | After ~10 customers |
| **Accounting systems** | No demand | On request |
| **Facebook / WhatsApp import** | Where field intel lives today, and tempting as an onboarding wedge. Platform terms and PII make it hazardous | Evaluate as a manual CSV import path instead (`TNR-116`) |
| **SMS gateway** | Only needed for Phase 2 trap alerts | Phase 2 |
| **Push notifications** | No Phase 1 use case worth the complexity; iOS PWA support is limited | Phase 2 with trap alerts |
| **Google Sheets sync** | Would perpetuate the spreadsheet chaos the product exists to end | No |

The WhatsApp/Facebook case deserves the note: it is where field intelligence lives today, so importing it is the
most obvious onboarding shortcut. It is also a terms-of-service and PII minefield. A documented manual CSV import
gets most of the value with none of the exposure.

## 9. Integration checklist

Before merging any new integration:

- [ ] Interface defined in the domain layer with a test fake
- [ ] Degraded mode documented and tested by a fault-injection test
- [ ] Timeout, retry policy and circuit-breaker threshold set explicitly
- [ ] Rate limiting on our side, respecting the provider's limits
- [ ] Credentials from the environment, schema-validated at boot
- [ ] EU data residency verified, or a documented justification
- [ ] Added to the sub-processor list if it processes personal data
- [ ] Cost impact estimated against the budget (`NFR-050`)
- [ ] Not on a critical write path, or an explicit ADR explaining why it must be
- [ ] Failure is visible to the user in honest language, never a silent degradation
