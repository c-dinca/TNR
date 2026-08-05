# User stories

Grouped by epic. Each story has testable acceptance criteria and cites the functional requirements it satisfies
(see [`03-functional-requirements.md`](03-functional-requirements.md)). Backlog items in
[`../05-delivery/02-backlog.md`](../05-delivery/02-backlog.md) reference these story IDs.

Format: `US-<epic><n>`. Priority: **P0** = MVP, cannot ship without; **P1** = first paying customer; **P2** = nice to have in Phase 1.

---

## Epic A — Organisation and access

### US-A1 · P0 · Create an organisation and become its owner
**As** an NGO coordinator, **I want** to register my organisation, **so that** my team's data is private to us.

- Given a valid email, name, password and org name, when I register, then an `org` is created, I hold role `owner`, and I am logged in.
- Passwords below the policy in `FR-002` are rejected with a field-level message.
- A duplicate email does not reveal whether an account exists (`FR-005`).
- An audit event `org.created` and `membership.created` are written.

Satisfies: `FR-001`, `FR-002`, `FR-005`, `FR-010`

### US-A2 · P0 · Invite a volunteer with a limited role
**As** Ana, **I want** to invite volunteers by email with role `volunteer`, **so that** they can submit sightings without seeing donor or financial data.

- An invitation produces a single-use token valid 14 days.
- Accepting creates a `membership` with exactly the invited role.
- A volunteer requesting a coordinator-only endpoint receives `403` with a problem document, and the attempt is logged.
- Re-inviting an existing member is idempotent and does not change their role.

Satisfies: `FR-011`–`FR-015`, `FR-030`

### US-A3 · P0 · Log in on a phone and stay logged in for a season
**As** Mihai, **I want** to log in once and not be asked again in the field, **so that** I never hit a login wall without signal.

- A successful login issues an access token (short-lived) and a refresh token (long-lived, rotating).
- With a valid refresh token the app restores a session with no network prompt beyond token refresh.
- If the device is offline at app start and a valid session exists locally, the field capture UI is fully usable.
- Logout clears the local database only after the outbox is empty, or after explicit confirmation of data loss.

Satisfies: `FR-003`, `FR-004`, `FR-006`, `NFR-011`

### US-A4 · P1 · Give a funder read-only visibility
**As** Ana, **I want** to grant a foundation officer read-only access to a campaign's reports, **so that** they can verify without me emailing files.

- A `funder` role can read campaign metrics, reports and evidence packs, and nothing else.
- A funder cannot see precise pack geometry, volunteer identities, or unrelated campaigns.
- Access is revocable and time-boxed; revocation takes effect within one token lifetime.

Satisfies: `FR-016`, `FR-031`, `FR-076`

---

## Epic B — Field capture (offline-first)

### US-B1 · P0 · Record a sighting in under 15 seconds
**As** Mihai, **I want** to log dogs I just saw with minimum taps, **so that** I actually do it every time.

- The capture screen is reachable in one tap from app launch.
- GPS position is pre-filled with accuracy shown; I can nudge the pin on a map.
- Required fields are location, `occurred_at` and estimated count only. Everything else optional.
- Submitting while offline stores the sighting locally, assigns it a client-generated UUIDv7, and shows it in "pending" state immediately.
- The whole flow completes in ≤ 15 s and ≤ 4 taps for the minimal case.

Satisfies: `FR-020`, `FR-021`, `FR-024`, `NFR-001`, `NFR-003`

### US-B2 · P0 · Attach photos that survive a bad connection
**As** Mihai, **I want** to attach photos, **so that** the coordinator can judge health and notch status.

- Up to 5 photos per sighting; each downscaled on-device to ≤ 1600 px long edge before storage (`NFR-004`).
- Photos are stored locally and uploaded independently of the sighting record; a failed photo never blocks the sighting.
- Upload retries with backoff and resumes after app restart.
- EXIF GPS and capture time are extracted and kept for evidence; EXIF is stripped from derivatives served to clients.

Satisfies: `FR-022`, `FR-023`, `FR-060`–`FR-064`

### US-B3 · P0 · Trust that nothing is lost
**As** Mihai, **I want** an unambiguous indicator of what has not yet reached the server, **so that** I stop worrying.

- A persistent badge shows the count of pending items, distinguishing "waiting for network" from "failed".
- Failed items expose a reason and a manual retry.
- Closing the app, rebooting the phone, or losing power does not lose pending items.
- Replaying the outbox never creates duplicates, verified by an idempotency test with a forced double-send.

Satisfies: `FR-025`–`FR-027`, `NFR-012`, `NFR-013`

### US-B4 · P1 · Note that a dog is already notched
**As** Mihai, **I want** to mark animals as already ear-notched, **so that** nobody wastes a cage on them.

- Sighting capture allows recording a count of visibly notched animals.
- Pack views show a notched/observed ratio.
- Route planning deprioritises packs above a configurable notched threshold.

Satisfies: `FR-028`, `FR-045`

### US-B5 · P2 · Work from a map I downloaded before losing signal
**As** Mihai, **I want** the map to still render in a village with no data, **so that** I can place a pin accurately.

- Basemap tiles for the org's operating region are cached for offline use.
- The cache is bounded and the app warns before exceeding a size budget.
- With no network, the map renders cached tiles and a clear indicator for uncached areas.

Satisfies: `FR-029`, `NFR-005`

---

## Epic C — Packs and animals

### US-C1 · P0 · See sightings clustered into packs
**As** Ana, **I want** nearby sightings grouped automatically, **so that** I plan against real colonies instead of individual pins.

- New synced sightings are evaluated against existing packs within a configurable radius and time window.
- A sighting within threshold is attached to the pack as evidence; otherwise a candidate pack is proposed.
- Clustering is advisory: every automatic decision is visible and reversible.
- Clustering runs asynchronously and never delays the sync response.

Satisfies: `FR-040`–`FR-042`, `NFR-002`

### US-C2 · P0 · Curate packs manually
**As** Ana, **I want** to merge, split, rename and close packs, **so that** the map reflects what I know from the ground.

- Merge moves all sightings/animals to the surviving pack and records the operation in the audit log.
- Split requires selecting which sightings move to the new pack.
- Closing a pack requires a reason from a fixed list (`resolved`, `relocated`, `duplicate`, `erroneous`).
- Every operation is reversible within 30 days via the audit trail.

Satisfies: `FR-043`, `FR-044`, `FR-091`

### US-C3 · P1 · Track individual animals
**As** Elena, **I want** to record identified animals, **so that** sterilisation status is attributable and coverage is real.

- An animal may be identified by microchip (15 digits, numeric), by ear-notch plus description, or by description only.
- A microchip number is unique within an org; conflicting entry is rejected with a link to the existing animal.
- Non-`642`-prefixed chips are accepted and flagged as non-Romanian.
- An animal's pack membership can change over time without losing history.

Satisfies: `FR-050`–`FR-053`

### US-C4 · P2 · Look up a microchip against public registries
**As** Elena, **I want** to check whether a chip is already registered, **so that** I know whether the dog is owned.

- Lookup is asynchronous, cached, and rate-limited per provider.
- Provider failure or timeout degrades to "unknown" and never blocks saving the animal.
- The result is stored with provider, timestamp and raw response for audit, and clearly labelled as unofficial.

Satisfies: `FR-054`, `FR-055`

---

## Epic D — Missions and routing

### US-D1 · P0 · Build a mission from selected packs
**As** Ana, **I want** to pick packs and turn them into a mission for a vehicle on a date, **so that** the team has an unambiguous plan.

- I can select packs on the map or from a list, and see aggregate estimated animals and cage capacity fit.
- A mission requires a date, a vehicle and at least one stop.
- Assigning a pack already covered by another mission on the same date raises a visible warning, not a silent block.
- Missions are visible to assigned members immediately after sync.

Satisfies: `FR-070`–`FR-072`

### US-D2 · P0 · Get an optimised stop order
**As** Ana, **I want** the system to order the stops, **so that** we stop wasting fuel.

- Optimisation returns an ordered stop list with distance, duration and a start/end depot.
- Vehicle cage capacity and a per-mission time window are respected.
- Optimisation of 25 stops returns in ≤ 10 s at p95; larger sets are queued with progress.
- If the routing engine is unavailable, a straight-line nearest-neighbour fallback is offered and clearly labelled as unoptimised.
- I can manually reorder afterwards; manual order is never overwritten without confirmation.

Satisfies: `FR-073`–`FR-076`, `NFR-006`

### US-D3 · P0 · Execute a mission offline
**As** Mihai, **I want** the mission on my phone with everything I need cached, **so that** I can work with no signal.

- Opening a mission while online caches stops, pack details, contact notes and map tiles for the corridor.
- Each stop can be marked arrived / completed / skipped with a reason, and animals captured recorded, offline.
- All stop outcomes queue in the outbox and sync later.
- Mission progress is visible to the coordinator as soon as it syncs, with the field-observed timestamps preserved.

Satisfies: `FR-077`–`FR-079`, `NFR-011`

### US-D4 · P1 · Compare planned versus actual
**As** Ana, **I want** to see planned vs. actual distance and completion, **so that** I can prove the fuel saving and improve planning.

- Mission detail shows planned km/duration against actual, derived from stop completion timestamps and locations.
- A campaign-level summary aggregates the saving.
- Missing actuals are shown as unknown, never as zero.

Satisfies: `FR-080`, `FR-081`

---

## Epic E — Interventions and evidence

### US-E1 · P0 · Record an intervention in under 60 seconds
**As** Elena, **I want** to log a sterilisation fast, **so that** admin does not eat the surgery day.

- Required: animal (existing or created inline), type, `occurred_at`, performing vet.
- Optional: anaesthesia details, notes, complications, ear-notch applied, chip implanted.
- The form works offline and queues; a chip number entered offline is validated locally for format.
- Once synced, an intervention is append-only: corrections create a superseding record referencing the original.

Satisfies: `FR-090`, `FR-092`, `FR-093`

### US-E2 · P0 · Photo evidence bound to the record
**As** Klaus, **I want** every claimed surgery to have traceable evidence, **so that** I can fund it.

- An intervention supports before/after photos; each stores capture time, GPS where available, and a SHA-256 content hash.
- Media cannot be replaced in place; a new version supersedes and both are retained.
- The evidence view shows hash, capture time and uploader for each photo.

Satisfies: `FR-094`, `FR-060`–`FR-064`, `FR-102`

### US-E3 · P0 · Tamper-evident history
**As** Klaus, **I want** assurance that records were not edited after the fact, **so that** the numbers mean something.

- Every create/update/delete of an intervention writes an audit event containing actor, timestamp, before/after diff, and the hash of the previous event.
- The chain is verifiable by an endpoint that reports the first broken link, if any.
- Audit events are not editable or deletable by any application role.

Satisfies: `FR-100`–`FR-103`

### US-E4 · P1 · Export the day's list for RECS entry
**As** Elena, **I want** a clean CSV of today's interventions, **so that** my legally required RECS entry is mechanical.

- Export covers a date range and includes chip number, species, procedure, date, vet, owner reference where known.
- Column layout matches the order the RECS form requires, documented in the integrations doc.
- Export is logged as an audit event including row count.

Satisfies: `FR-056`, `FR-104`

---

## Epic F — Reporting

### US-F1 · P0 · See campaign progress on one screen
**As** Ana, **I want** a dashboard for a campaign, **so that** I know where we stand without building a spreadsheet.

- Shows interventions by type over time, packs covered vs. identified, coverage estimate by locality, active missions.
- Loads in ≤ 2 s at p95 for 50,000 interventions.
- Every number is clickable through to the underlying records.

Satisfies: `FR-110`–`FR-112`, `NFR-007`

### US-F2 · P0 · Generate a donor report
**As** Ana, **I want** a PDF for a grant period, **so that** I stop assembling reports by hand.

- Report covers a date range and campaign, in English, German or Romanian.
- Contains intervention counts by type and locality, cost per intervention if costs were entered, coverage change, a map, and an evidence sample.
- Generation is asynchronous with a download link; the same input yields a byte-stable document for the same data snapshot.
- Generating a report writes an audit event.

Satisfies: `FR-113`–`FR-116`

### US-F3 · P1 · Produce a verifiable evidence pack
**As** Klaus, **I want** an archive I can independently verify, **so that** my board is satisfied.

- Pack contains the PDF summary, a media manifest with hashes, the interventions as CSV, and an audit-chain excerpt.
- A `VERIFY.md` explains how a third party checks the hashes without our software.
- The pack itself is hashed and that hash is recorded in the audit log.

Satisfies: `FR-117`, `FR-118`, `FR-105`

### US-F4 · P2 · Coverage map by locality
**As** Ana, **I want** to see which localities are under-covered, **so that** I aim the next campaign at them.

- Choropleth over administrative units using estimated population against interventions.
- Localities with no data are visually distinct from localities with zero coverage.
- Precise pack geometry is never rendered in any funder-visible view.

Satisfies: `FR-119`, `FR-031`

---

## Epic G — Platform and compliance

### US-G1 · P0 · Nothing crosses org boundaries
**As** Ana, **I want** certainty that another NGO cannot see my data, **so that** I can put real locations in.

- Every tenant-scoped endpoint filters by `org_id` derived from the session, never from client input.
- An automated test suite attempts cross-org access on every endpoint and expects `404`/`403`.
- A missing `org_id` filter fails a static check in CI.

Satisfies: `FR-030`–`FR-033`, `NFR-030`

### US-G2 · P0 · Handle a data subject request
**As** the operator, **I want** to export or erase a person's data on request, **so that** we are GDPR-compliant.

- Export produces machine-readable data for a given user within the statutory window.
- Erasure removes personal identifiers while preserving anonymised operational records needed for donor audit, with the legal basis for retention documented.
- Both actions are audit-logged and require an admin role plus explicit confirmation.

Satisfies: `FR-120`–`FR-123`

### US-G3 · P1 · Recover from a bad day
**As** the operator, **I want** verified backups and a rehearsed restore, **so that** an outage is not an extinction event.

- Automated daily backups with point-in-time recovery, retained per the infrastructure doc.
- A quarterly restore rehearsal is documented with the measured RTO.
- Media in object storage is versioned so an overwrite is recoverable.

Satisfies: `NFR-020`–`NFR-023`

### US-G4 · P1 · Use the app in Romanian
**As** Mihai, **I want** the whole field UI in Romanian, **so that** I do not misread anything.

- All user-facing strings come from a translation catalogue; no hard-coded copy.
- Romanian is the default for users with a Romanian locale; language is switchable per user.
- Dates, numbers and units follow locale; coordinates are always decimal degrees.
- A CI check fails on a missing translation key for a shipped locale.

Satisfies: `NFR-021`, `NFR-022`
