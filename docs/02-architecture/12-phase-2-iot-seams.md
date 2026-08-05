# Phase 2 IoT seams

**This document specifies what Phase 1 must build so that Phase 2 is additive. It does not authorise building
Phase 2.**

An agent reading this should implement only §5, "What Phase 1 builds". Everything else is context, so that the
small amount built now is built in the right shape.

---

## 1. What Phase 2 is

Retrofit IoT sensor modules that clamp onto any standard wire-mesh trap cage:

- **MCU**: ESP32 family (deep sleep, cheap, well documented).
- **Connectivity**: NB-IoT or LTE-M — low-power WAN standards with good Romanian coverage from Orange and Vodafone.
- **Trigger**: magnetic reed switch or IR beam detecting the cage door closing.
- **Protocol**: on trigger, wake from deep sleep, attach to the network, publish a minimal JSON payload over MQTT
  to the TNR-OS ingest endpoint, sleep again.
- **Enclosure**: IP67, 3D-printed or off-the-shelf. The founder does not become a metalworker; the moat is the
  code, not the cage.

**Problem solved:** manual trapping requires a volunteer to wait for hours in the cold or physically re-check
empty cages several times a day. Automation removes >90% of patrol time and prevents a trapped animal from being
left exposed to weather or predators. One operator can run fifty traps across tens of kilometres.

## 2. Why it is not Phase 1

Hardware first would mean inventory, certification, logistics and support before any workflow is validated. And
the sensor's value is the *notification* — which requires a platform that operators already open every morning,
with the pack, mission and volunteer records to route an alert to. That platform is Phase 1.

Trigger conditions (from [`../00-context/01-problem-and-vision.md`](../00-context/01-problem-and-vision.md)) —
**all** must hold:

- ≥ 3 paying NGO organisations, ≥ 12 months combined retention
- ≥ 5,000 interventions recorded through the platform
- ≥ 20 vehicles coordinated in a single season
- Customers independently asking for cage monitoring

## 3. Target Phase 2 flow

```
Cage door closes
  → reed switch closes → ESP32 wakes from deep sleep
  → LTE-M/NB-IoT attach (5–30 s)
  → MQTT CONNECT (mutual TLS or per-device token) to ingest.tnr-os.dev
  → PUBLISH tnr/v1/device/{hardware_id}/event
       { "type":"capture", "ts":1780000000, "battery_mv":3812, "rssi":-97, "seq":41 }
  → deep sleep
        ↓
MQTT bridge authenticates the device, resolves org + assigned pack,
calls the SAME domain service a controller calls
  → creates a sighting with source='device'
  → creates a capture event
  → audit event with actor_type='device'
  → enqueues notify-nearest-volunteer
        ↓
Push/SMS to the nearest volunteer with the trap location and a "responding" acknowledgement
```

The critical property: the bridge is a **transport adapter**. It performs no business logic of its own. It
authenticates, translates and calls the same service layer as HTTP. That is the whole point of designing the seam
now.

## 4. What would be expensive to retrofit

These are the reasons the seams are worth a few hours of Phase 1 work:

| Concern | Cost if not designed now |
|---|---|
| Non-human actors in the audit chain | Adding `actor_type` later means backfilling every event and bumping `chain_version` — invalidating every published verification instruction |
| Machine-originated sightings | Adding `source`/`device_id` to a large `sighting` table later is a slow migration and a reporting-logic change everywhere |
| Device identity | Retrofitting a credentialed non-user principal into an auth model built solely around `membership` is genuinely invasive |
| Event ingest that is not HTTP | If business rules live in controllers, a second transport means duplicating them — the single most common cause of divergent behaviour |
| Telemetry storage shape | Battery and signal history has different write characteristics; knowing it is coming prevents shoehorning it into `sighting` |

## 5. What Phase 1 builds

**Only these five things. Nothing else.**

### 5.1 The `device` table

Already specified in [`02-data-model.md`](02-data-model.md) §3.15:

```
device(id, org_id, hardware_id UNIQUE, label, kind, status,
       credential_hash, last_seen_at, firmware_version, assigned_pack_id,
       created_at, updated_at, deleted_at)
```

Table plus repository plus a hidden admin-only CRUD endpoint. No UI, no provisioning flow, no fleet management.

### 5.2 `source` and `device_id` on `sighting`

```
sighting.source     text NOT NULL DEFAULT 'field_app'   -- field_app | import | device
sighting.device_id  uuid NULL REFERENCES device(id)
CONSTRAINT ck_sighting_device CHECK (source <> 'device' OR device_id IS NOT NULL)
```

Every reporting query and every UI surface must therefore handle a sighting with no `reported_by_user_id` from day
one. That is the actual seam: the assumption "every sighting has a human author" is what would otherwise be baked
into fifty places.

### 5.3 `actor_type` in the audit chain

`actor_type` is `user | system | device` and is **part of the hash input** from the very first event
([`08-audit-and-donor-reporting.md`](08-audit-and-donor-reporting.md) §2). Phase 1 already uses `system` for
clustering decisions, so the code path is exercised; `device` is unused but valid.

Including it in the hash now is the single highest-value seam in this document. Adding a field to the canonical
form later would invalidate every `VERIFY.md` instruction we have shipped to funders.

### 5.4 A transport-agnostic service layer

Enforced by existing rules rather than new code: controllers contain no business logic, services never import HTTP
types ([`01-system-overview.md`](01-system-overview.md) §4). The verification is that workers already call the same
services with a `SystemContext`. If a job can create a sighting, so can an MQTT bridge.

`SightingService.create(ctx, input)` where `ctx` is `UserContext | SystemContext | DeviceContext` — the third
variant is declared in Phase 1 as a type, unconstructed.

### 5.5 A documented event contract

The MQTT payload shape is fixed now so firmware and platform cannot drift, and the versioned topic exists from the
start:

```
Topic:    tnr/v1/device/{hardware_id}/event
Payload:  { "type": "capture" | "heartbeat" | "door_open" | "tamper" | "low_battery",
            "ts": <unix seconds, device clock>,
            "seq": <monotonic counter, the idempotency unit>,
            "battery_mv": <int>, "rssi": <int>,
            "meta": { ... optional ... } }
QoS 1, payload ≤ 256 bytes.
```

`seq` is the idempotency key: NB-IoT delivery is unreliable and QoS 1 is at-least-once, so `(device_id, seq)` must
be unique. This mirrors the offline outbox's `op_id` exactly — the same problem, the same solution, which is a good
sign the design is coherent.

Payloads stay under 256 bytes because NB-IoT throughput is tiny and every byte costs battery.

## 6. Phase 2 work, explicitly deferred

| Deferred | Notes |
|---|---|
| MQTT broker + bridge service | EMQX or Mosquitto; the bridge is a thin adapter over existing services |
| Device provisioning and credential rotation | Per-device tokens or mTLS; QR-code claim flow |
| `device_telemetry` table | Battery/signal time series; likely a separate table with aggressive retention |
| Fleet management UI | Map of traps, battery status, last-seen, assignment |
| Alerting to the nearest volunteer | Push (web push or native), SMS fallback; requires an on-call rota model |
| Trap-to-pack assignment workflow | Which trap covers which pack |
| Firmware, OTA updates | Whole workstream of its own |
| M2M SIM management and cost model | Per-SIM data plan is the recurring cost driving Phase 2 pricing |
| Welfare escalation | If a captured animal is not collected within N minutes, escalate. **The most important Phase 2 feature**, and the one that justifies the whole product ethically |
| Offline device buffering | Store-and-forward when the network is unavailable |

## 7. Rules for Phase 1 agents

1. Build only §5. If a backlog item does not name a §5 item, do not touch device code.
2. Do not add device UI. Not a nav entry, not a settings page.
3. Do not add MQTT dependencies. Not the broker, not a client library.
4. Do **not** change the audit canonical form to "prepare" for anything. It is already correct.
5. When writing a query or a UI over sightings, handle `reported_by_user_id IS NULL`. That is the seam working.
6. If a design decision would make §3's flow harder, say so in the PR. That is exactly the feedback this document
   exists to collect.

## 8. Open questions

> **OQ-IOT-1** — MQTT versus HTTP POST from the device. HTTP is simpler to secure and requires no broker; MQTT is
> more power-efficient for persistent sessions. Given the device sleeps between rare events, a single HTTPS POST may
> genuinely be better. **Decide in Phase 2 with real power measurements** — the topic string above is a placeholder,
> and the event *payload* contract is what matters and is transport-independent.

> **OQ-IOT-2** — Should a device-originated capture create a `sighting`, or a distinct `capture_event` entity? A
> capture is a different kind of fact from a sighting. Leaning toward a `capture_event` referencing a device and a
> trap, with a derived sighting for map continuity. Not decided; noted so nobody assumes.
