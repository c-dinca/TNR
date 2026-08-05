# Problem and vision

## The crisis

Romania has the largest stray-dog population in the European Union: between **500,000 and 1,000,000** animals
depending on whether official or NGO estimates are used. The root cause is historical. Communist-era forced
urbanisation moved millions of people from rural houses into urban apartment blocks, and the dogs they left
behind bred freely.

After a widely publicised fatal attack in 2013, Romania passed **Law 258/2013**, which permits capture and
euthanasia of strays not claimed or adopted within fourteen working days of impoundment. Between 2001 and 2018
more than **144,000 dogs** were killed under this and predecessor regimes, frequently in conditions
international observers judged inhumane.

**Culling does not work.** The population regenerates continuously because the inflow is never addressed:

1. Chronic abandonment, concentrated in rural areas and small towns.
2. Unsterilised yard dogs (`câini de curte`) that roam and breed uncontrolled.
3. Unwanted litters dumped in fields and forests.

Only two levers actually reduce the population without killing animals:

- **Trap–Neuter–Return (TNR)** at sufficient density and coverage to break the breeding cycle.
- **Export adoption** to Western Europe (Germany, Switzerland, UK), the system's main relief valve.

Both are executed today by chronically underfunded NGOs and mobile veterinary clinics, and both are crippled by
operational friction rather than by lack of will.

## The specific friction TNR-OS attacks

A TNR campaign in rural Romania currently runs like this: a volunteer hears from a villager that there are dogs
near a particular farm. That is relayed into a WhatsApp group. Someone writes it in a spreadsheet. A mobile
clinic drives out — often several hundred kilometres — using a route someone sketched from memory. Cages are
placed and then physically checked every few hours. Half the dogs trapped turn out to be already ear-notched
(already sterilised), so the trip was partly wasted. At the end, the NGO has to prove to a German or Swiss
foundation that the money bought surgeries, and it does so with a folder of unsorted photos and a hand-typed
list.

The measurable consequences:

| Friction | Effect |
|---|---|
| Intelligence lives in chat groups | Sightings are lost, duplicated, or acted on twice |
| Routes planned by memory | Empty vehicle-kilometres; fuel is a top-three cost line |
| No way to know a dog is already sterilised before trapping it | Wasted cage-hours and needless animal stress |
| Evidence is a folder of photos | Grant applications fail or are under-funded; ROI cannot be shown |
| Every NGO rebuilds its own spreadsheet | No shared picture of coverage; no way to see which villages were never reached |

Every one of these is a **software** problem. None of them requires hardware to fix.

## The "Software Wedge" strategy

The founder is a solo technical operator: full-stack engineering, cloud infrastructure, DevOps. The correct
market-entry shape for that profile is a software wedge:

**Phase 1 — software only.** A pure SaaS product has near-zero marginal distribution cost, infinite elasticity,
and — critically — avoids the slow, politicised, often corrupt procurement cycles of Romanian government sales
(B2G). It sells to private and non-profit actors who can decide in a week. It removes an immediate operational
pain, creates tool dependence, and begins accumulating a proprietary data set (a *data moat*): where the packs
are, which are sterilised, which villages are unserved, what a surgery actually costs.

**Phase 2 — hardware, only after the software is load-bearing.** Once the major NGOs run their operations on
TNR-OS, IoT trap sensors are added. They are not a new product; they are a new input to an API that already
exists, feeding a dashboard operators already open every morning. That combination of bits and atoms is
extremely hard for a competitor to replicate: they would have to displace both the workflow and the fleet.

The sequencing is deliberate. Hardware first would mean inventory risk, certification, logistics and support
before a single validated workflow. Software first means the hardware ships into an installed base that has
already told us what it wants the sensor to do.

## What Phase 1 must prove

Phase 1 is successful if, within one campaign season, a single NGO customer can say all four of:

1. "We no longer plan capture trips from WhatsApp."
2. "We drive measurably fewer empty kilometres."
3. "We won a grant using a report this system generated."
4. "If you turned it off tomorrow we could not run a campaign."

Point 4 is the wedge. Points 1–3 are how we earn it.

## What triggers Phase 2

Phase 2 development starts when **all** of the following hold (see
[`../05-delivery/01-roadmap.md`](../05-delivery/01-roadmap.md)):

- ≥ 3 paying NGO organisations, ≥ 12 months combined retention
- ≥ 5,000 interventions recorded through the platform
- ≥ 20 vehicles coordinated in a single season
- Customers independently asking for cage-monitoring automation

Building trap sensors before those conditions is premature and is explicitly out of scope. What Phase 1 *does*
owe Phase 2 is a set of architectural seams — device identity, event ingest, telemetry storage — specified in
[`../02-architecture/12-phase-2-iot-seams.md`](../02-architecture/12-phase-2-iot-seams.md) and cheap to build
now, expensive to retrofit later.

## Non-goals

TNR-OS is not, in Phase 1:

- a government reporting system or a public-sector procurement product;
- a replacement for the national microchip registry (RECS) — we read from public lookups, we never claim to write to it;
- a veterinary practice-management or clinical-records system;
- an adoption marketplace or a donation platform;
- a public "report a stray" app for the general population. Untrusted crowdsourced input would poison the data
  moat before it forms; public intake is considered only after operator trust levels exist (`TNR-115`).

## Ethical position

The product exists to reduce the stray population without euthanasia. Design decisions follow from that:

- Sterilisation and return is the default modelled outcome; euthanasia is recordable only as a
  veterinarian-attested medical decision, never as a population-control action.
- Location data about animals is sensitive. Publishing precise pack coordinates would enable poisoning and
  abuse, so precise geometry is never exposed outside the owning organisation — see
  [`../02-architecture/11-security-and-gdpr.md`](../02-architecture/11-security-and-gdpr.md).
- The system must not become a targeting tool for municipal capture-and-kill contractors. Access is granted per
  organisation, and the terms of service prohibit that use.
