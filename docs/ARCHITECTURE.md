# Go-Ye system architecture and phase plan

**Prepared:** 2026-11-06
**Status:** Phase 0 baseline — no real convert data permitted

## 1. Mission and non-negotiable outcomes

Go-Ye is an offline-first, easy-to-use soul-winning and follow-up system for RCCG. It serves Android 8+, iOS 15+ and Windows 10/11 from one Flutter codebase and one NestJS/PostgreSQL backend. A record entered on one device must synchronise to every authorised device at its eligible church scope.

The requirement artefacts reviewed for this baseline are `proposal.docx` and `soulwinning.png`. The latter's implementation flow informs the delivery gates: stakeholder requirements, architecture, Modules A/B/C, integration and security, testing/pilot feedback, deployment, training and continuous improvement.

The implementation will never treat a dashboard as the source of truth. The source is the consented convert journey and auditable organisational hierarchy.

## 2. Delivery phases and approval gates

| Phase                                           | Scope                                                                                                                                                | Exit evidence                                                                                                           | Approval needed before       |
| ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- | ---------------------------- |
| 0 — Foundation and skeleton                     | Requirements traceability, safe defaults, monorepo directories, API/DB dev stack, Flutter shell, tooling and CI scaffold.                            | Reproducible development instructions, hello API, test/lint configuration, ERD, CI workflow and documented limitations. | Secure platform/domain work. |
| 1 — Secure platform foundation                  | Monorepo tooling; Flutter shell; NestJS API; PostgreSQL migrations; health checks; auth/roles; hierarchy, RLS and audit primitives; CI.              | Reproducible local stack, migrations up/down notes, contract and security tests.                                        | Storing pilot identities.    |
| 2 — Convert Journey (Module B)                  | Consent-first 60-second offline New Decision, encrypted PII, duplicate review/merge, routing/Unassigned Pool, journey timeline and privacy requests. | Android/offline/device tests; server scope tests; pilot-ready privacy review inputs.                                    | Pilot conversion data.       |
| 3 — Follow-Up (Module C)                        | Assignment, default/versioned schedules, Today list, one-tap outcomes, idempotent scheduler, escalation and neglected lists.                         | Clock/idempotency/escalation tests and operational runbook.                                                             | Pilot campaign.              |
| 4 — Sharing and insight (Module A + dashboards) | Multilingual tract CMS/library, share links/landing page/analytics, reports, exports and monthly report.                                             | Access-controlled analytics/export tests and accessibility review.                                                      | Wider rollout.               |
| 5 — Hardening and release                       | Notification providers, observability, backup-restore drill, security review, training/handover and signed release CI.                               | Release manifest, restore evidence, test suite and platform build results.                                              | Production rollout.          |

At each phase end, work pauses for explicit sponsor approval. No later phase is silently started.

## 3. Actors and enforceable access

| Actor                                            | Primary capability                                                                  | Visibility rule                                                                            |
| ------------------------------------------------ | ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| Global Admin                                     | Global organisation, policy, reports and approved administration.                   | Every country independently, country/region totals and grand total; drill-down is audited. |
| Country / Region / Province / Zone / Area leader | Register local converts, administer authorised local workflow and inspect roll-ups. | Home unit plus descendants only.                                                           |
| Parish pastor                                    | Parish oversight and may grant/revoke restricted worker access.                     | Parish scope, subject to higher authorised scope.                                          |
| Soul-winner / follow-up worker                   | Register consented convert, complete assigned follow-ups and use tracts.            | Assigned converts only at parish level unless a pastor grants broader scope.               |
| Content administrator                            | Manage tract content and translations.                                              | No convert PII by virtue of this role.                                                     |
| Privacy officer                                  | Process access/correction/removal matters.                                          | Least-privilege, separately audited access.                                                |

A single user has one home unit. The hierarchy is strict: `COUNTRY > REGION > PROVINCE > ZONE > AREA > PARISH`.

```text
GLOBAL ADMIN
  COUNTRY
    REGION
      PROVINCE
        ZONE
          AREA
            PARISH
```

For every non-global request the server derives `home_unit.path` and permits only matching descendant paths. UI hiding is convenience; PostgreSQL row-level security (RLS) and API query predicates are the enforcement points.

## 4. Functional requirements traceability

| Requirement / user story                                                          | Planned bounded context | Acceptance evidence                                                                     |
| --------------------------------------------------------------------------------- | ----------------------- | --------------------------------------------------------------------------------------- |
| A worker shares a suitable tract in a recipient's language.                       | Content/Sharing         | Language selection, native share-sheet event and short-link test.                       |
| An interested recipient opens a trackable public link without installing the app. | Public landing          | Privacy-safe link/open events; no PII in URL or analytics.                              |
| A worker records a new decision in about 60 seconds even offline.                 | Convert Journey + sync  | One-screen form, required consent, queued create, reconnect test.                       |
| A leader at any level can register for their own church.                          | Convert Journey         | Valid registering-unit scope test for every hierarchy level.                            |
| A non-parish registration is accountable until it reaches a parish.               | Assignment              | Unassigned Pool, age counter, manual assignment audit and neglected visibility test.    |
| A convert is guided from New to Fully Planted.                                    | Journey                 | Immutable stage/timeline records and authorised transition tests.                       |
| A parish worker is reminded and can mark work done quickly.                       | Follow-Up               | Today list, one-tap outcome/note, server idempotency test.                              |
| A supervisor notices neglected souls without seeing unauthorised PII.             | Follow-Up + reporting   | Escalation/role/masked-phone tests.                                                     |
| Leaders see correct roll-ups without double counting.                             | Reporting               | Hierarchy fixture and summary-vs-source comparison tests.                               |
| A person can request removal and exercise data rights.                            | Privacy                 | Permission/authentication workflow, quarantined access and erasure/anonymisation tests. |
| A pastor receives monthly evidence rather than handwritten totals.                | Reporting               | Scoped, reproducible export/report test.                                                |

## 5. Core data model (logical)

All tables receive UUID primary keys, UTC timestamps, actor/audit metadata and migration-owned constraints. Names below are intentionally logical; Phase 1 will turn them into versioned SQL migrations.

| Entity                                                        | Key fields and rules                                                                                                                                                         |
| ------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `org_units`                                                   | `id`, `type`, `name`, unique `code`, `parent_id`, indexed `path ltree`, `is_active`. Parent-type and cycle rules are database-enforced.                                      |
| `users` / `user_roles`                                        | One nullable-only-for-global `home_unit_id`; explicit roles; active/locked state.                                                                                            |
| `access_grants`                                               | Pastor-authorised, time-bounded widening for restricted parish workers.                                                                                                      |
| `converts`                                                    | Registering unit/by, nullable parish, encrypted name/phone/address/location, decision date, age band, current stage, consent reference, privacy status, optimistic revision. |
| `consents`                                                    | Version, affirmative flag, timestamp, actor, capture method and locale. Saving a convert requires it.                                                                        |
| `convert_events`                                              | Append-only stage/assignment/contact/merge/removal timeline.                                                                                                                 |
| `follow_up_plans` / `follow_up_tasks`                         | Versioned schedule, due time, assignee, status/outcome/note, escalation state and idempotency key.                                                                           |
| `duplicate_candidates` / `convert_merges`                     | Controlled review/merge with source-to-survivor lineage; no silent deletion.                                                                                                 |
| `tracts`, `tract_translations`, `share_links`, `share_events` | Versioned multilingual media/content, expiring/public-safe tokens and pseudonymous events.                                                                                   |
| `unit_daily_summaries`                                        | Incrementally maintained reporting facts keyed by day and unit.                                                                                                              |
| `audit_log`                                                   | Append-only actor/action/scope/record metadata, previous chain hash and HMAC; PII excluded.                                                                                  |
| `outbox_events` / `sync_receipts`                             | Transactional change publishing and device idempotency receipts.                                                                                                             |
| `tenant_settings`                                             | Server-enforced settings including `mask_phone_numbers_above_parish = false`.                                                                                                |

### Data-flow constraints

1. The client stores a consented draft locally. A draft lacking affirmative consent may be discarded locally and **must not** enter the sync outbox.
2. Sync sends an idempotency key. The server authorises the registering unit, verifies consent and validates the payload before transactionally creating the convert, audit event, follow-up plan (when parish-assigned) and outbox event.
3. Workers fetch only a scoped sync delta. The API never sends all records to a client and expects it to filter.
4. A read of convert details by an actor above parish scope is logged in the same transaction as the detail access.
5. Reporting reads summary facts for speed and has a bounded fresh-data fallback/rebuild path. Privacy/export views apply masking before serialization.

## 6. Follow-up lifecycle

```text
New Convert
  ├─ Day 1: call due within 24h
  ├─ Day 3: prayer follow-up
  ├─ Day 7: visit follow-up
  └─ weekly thereafter (policy-configurable)
       ↓
Believers' Class → Baptismal Class → Baptised → Parish Integration (Fully Planted)
```

Missed tasks transition through a documented escalation ladder to the relevant supervisor. Firebase Cloud Messaging (FCM) is the primary push channel; Windows presents synced assignments as local notifications. A task is not treated as complete merely because a notification was delivered. Completion records the outcome, note and actor/time. The scheduler uses unique task keys and transaction locking so replaying a job cannot create duplicate reminders or escalation records.

## 7. Security and privacy baseline

- TLS only outside local development; production HSTS/security headers/certificate renewal monitoring.
- Phone/address field encryption; key IDs stored with ciphertext to allow rotation. Search/dedup uses a protected normalized derivative, never plaintext logging.
- Argon2/hashing for refresh/session tokens; only hashes persist.
- Short access tokens and rotating/revocable refresh tokens; remote logout invalidates session family.
- OTP rate limits, lockouts, abuse monitoring and generic enumeration-safe responses.
- DTO validation, parameterised queries, safe file/media handling, CSP/security headers, dependency scanning and secret scanning.
- Least privilege app/migration/reporting roles; RLS policy tests run against a non-owner DB connection.
- Tamper-evident audit verification and daily backups with a tested restore procedure.
- Legal/privacy counsel must approve notice text, lawful basis, retention schedule and cross-border processing before production collection.

## 8. Scale and operations

PostgreSQL `ltree` GiST indexes support descendant scope. High-volume reporting uses day/unit summaries rebuilt from immutable source events and checked by periodic reconciliation. Workers communicate through a durable database-backed outbox at first; a managed queue can be added later without changing domain contracts. Media uses object storage/CDN rather than database blobs. Databases are never exposed publicly.

Monitoring will cover sync failures, task backlog/age, notification result, OTP abuse, API error rate, audit-chain verification, backup freshness, restore exercise outcome and monthly billable-message usage. SMS/WhatsApp sending stops before exceeding a configured hard cap.

## 9. Build, test and release matrix

| Deliverable                                    | CI runner | Signing prerequisite                                | What this Linux workspace can honestly do                                              |
| ---------------------------------------------- | --------- | --------------------------------------------------- | -------------------------------------------------------------------------------------- |
| Backend Docker image/OpenAPI                   | Linux     | Church registry/deploy credentials                  | Build and test.                                                                        |
| Android `.apk` / `.aab`                        | Linux     | Church Android upload/app-signing key in CI secrets | Build unsigned/test artifacts if SDK is available; signed release only in CI with key. |
| iOS archive / `.ipa`                           | macOS     | Xcode + Apple Developer certificates/profiles       | Cannot build/sign here. Workflow will be provided.                                     |
| Windows portable `GoYe.exe` / `GoYe-Setup.exe` | Windows   | Windows signing certificate for release             | Cannot build installer here. Workflow will be provided.                                |

Each release includes tests, software bill of materials/dependency scan, migration compatibility result, artifact hashes and a statement of actual signatures/platform outputs. No absent signed file will be claimed.

## 10. Pilot and operational guardrails

The first pilot remains small (five parishes, approximately 30–100 users) and only begins after sponsor approval, privacy review, staff training and tested restore. It must measure the proposal's success metrics: tract shares/opens, decisions, 24-hour contact rate, follow-up completion, baptism/planting in six months, neglected count, active workers/parishes and cost per followed soul. Pilot feedback routes to refinements before a rollout gate.
