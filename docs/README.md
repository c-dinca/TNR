# TNR-OS documentation

This is the complete specification for TNR-OS Phase 1. It is written to be executable by multiple independent
agents: each document states what is decided, what is deliberately open, and which backlog items depend on it.

**If you are an agent, read [`../AGENTS.md`](../AGENTS.md) first.**

---

## Reading paths

**"I need to understand the problem"** → `00-context/01` → `00-context/02` → `00-context/03`

**"I need to build a feature"** → `05-delivery/02-backlog.md` (find item) → the item's *Reading* list → `05-delivery/04-definition-of-done.md`

**"I need to make a technical decision"** → `03-adr/` (check it isn't already decided) → `03-adr/0000-template.md`

**"I need to set up my machine"** → `04-engineering/02-local-dev-setup.md`

---

## 00 — Context

| Doc | Contents |
|---|---|
| [`01-problem-and-vision.md`](00-context/01-problem-and-vision.md) | The Romanian stray-dog crisis, why software first, what winning looks like |
| [`02-ecosystem-and-stakeholders.md`](00-context/02-ecosystem-and-stakeholders.md) | NGOs, vets, rural citizens, transporters, the legal frame, RECS |
| [`03-glossary.md`](00-context/03-glossary.md) | **Binding vocabulary.** Every domain term used in code, DB, API and UI |
| [`04-business-model.md`](00-context/04-business-model.md) | Who pays, pricing, unit economics, the Phase 2 hardware pivot |

## 01 — Product

| Doc | Contents |
|---|---|
| [`01-scope-and-personas.md`](01-product/01-scope-and-personas.md) | Phase 1 in/out of scope, the three personas, their device reality |
| [`02-user-stories.md`](01-product/02-user-stories.md) | Stories with acceptance criteria, grouped by epic |
| [`03-functional-requirements.md`](01-product/03-functional-requirements.md) | Numbered `FR-###` requirements — traceable from stories to tests |
| [`04-non-functional-requirements.md`](01-product/04-non-functional-requirements.md) | `NFR-###`: performance, offline, availability, accessibility, i18n |

## 02 — Architecture

| Doc | Contents |
|---|---|
| [`01-system-overview.md`](02-architecture/01-system-overview.md) | Context/container/component views, request flows, failure modes |
| [`02-data-model.md`](02-architecture/02-data-model.md) | Entities, relationships, invariants, lifecycle state machines |
| [`03-api-design.md`](02-architecture/03-api-design.md) | REST conventions, resources, idempotency, errors, pagination |
| [`04-geospatial-and-routing.md`](02-architecture/04-geospatial-and-routing.md) | PostGIS usage, pack clustering, route optimisation, map tiles |
| [`05-offline-first-and-sync.md`](02-architecture/05-offline-first-and-sync.md) | Outbox pattern, conflict resolution, media queue, sync protocol |
| [`06-auth-and-tenancy.md`](02-architecture/06-auth-and-tenancy.md) | Sessions, tokens, orgs, roles, permission matrix, invitations |
| [`07-media-and-ml-pipeline.md`](02-architecture/07-media-and-ml-pipeline.md) | Photo upload, EXIF, derivatives, ear-notch detection seam |
| [`08-audit-and-donor-reporting.md`](02-architecture/08-audit-and-donor-reporting.md) | Tamper-evident audit log, grant reports, evidence packs |
| [`09-infrastructure-and-devops.md`](02-architecture/09-infrastructure-and-devops.md) | Environments, deploy topology, IaC, backups, cost envelope |
| [`10-observability-and-slos.md`](02-architecture/10-observability-and-slos.md) | Logs, metrics, traces, SLOs, alerting, on-call for a solo founder |
| [`11-security-and-gdpr.md`](02-architecture/11-security-and-gdpr.md) | Threat model, GDPR lawful basis, retention, DSR handling |
| [`12-phase-2-iot-seams.md`](02-architecture/12-phase-2-iot-seams.md) | What Phase 1 must build now so trap sensors plug in later |
| [`13-integrations.md`](02-architecture/13-integrations.md) | RECS/RomPetID microchip lookup, TRACES NT, SMS, email, maps |

## 03 — Decisions (ADR)

[`03-adr/`](03-adr/) — one file per decision, immutable once accepted, superseded rather than edited.
Index: [`03-adr/README.md`](03-adr/README.md).

## 04 — Engineering

| Doc | Contents |
|---|---|
| [`01-repo-structure.md`](04-engineering/01-repo-structure.md) | Monorepo layout, package boundaries, dependency rules |
| [`02-local-dev-setup.md`](04-engineering/02-local-dev-setup.md) | Prerequisites, bootstrap, seed data, common tasks |
| [`03-coding-standards.md`](04-engineering/03-coding-standards.md) | Naming, error handling, module patterns, React conventions |
| [`04-testing-strategy.md`](04-engineering/04-testing-strategy.md) | Test pyramid, fixtures, spatial and offline testing |
| [`05-git-and-review-workflow.md`](04-engineering/05-git-and-review-workflow.md) | Branching, commits, PR template, review checklist |
| [`06-ci-cd.md`](04-engineering/06-ci-cd.md) | Pipeline stages, gates, migration safety, rollback |

## 05 — Delivery

| Doc | Contents |
|---|---|
| [`01-roadmap.md`](05-delivery/01-roadmap.md) | Milestones M0–M5, sequencing, what triggers Phase 2 |
| [`02-backlog.md`](05-delivery/02-backlog.md) | **The work queue.** `TNR-###` items with reading lists and file boundaries |
| [`03-agent-playbook.md`](05-delivery/03-agent-playbook.md) | How an agent picks up, executes and hands off an item |
| [`04-definition-of-done.md`](05-delivery/04-definition-of-done.md) | The checklist that gates "complete" |

---

## Document conventions

- **MUST / SHOULD / MAY** are used in the RFC 2119 sense.
- `FR-###`, `NFR-###`, `TNR-###`, `ADR-####` identifiers are stable. Never renumber; mark as withdrawn instead.
- **Open question** blocks mark deliberate gaps. An agent encountering one must not invent an answer silently — resolve it in an ADR or escalate.
- Anything not stated as decided is not decided.
