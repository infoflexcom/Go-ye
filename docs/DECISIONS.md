# Go-Ye architecture decisions

This register records the safe defaults adopted while requirements remain open. It is deliberately append-only: a later change should add a dated superseding entry rather than rewrite history.

## ADR-001 — Monorepo and shared contracts

**Date:** 2026-11-06
**Status:** Accepted

Use one church-owned repository with:

- `app/` — Flutter application for Android, iOS and Windows;
- `backend/` — NestJS TypeScript REST API and worker processes;
- `infra/` — Docker, database and operational configuration;
- `docs/` — architecture, operations, privacy, handover and phase records;
- `scripts/` — repeatable developer, migration, build and release commands.

OpenAPI is generated from the NestJS API and checked into an export during release. A typed Dart client will be generated from that contract rather than manually duplicated. This reduces drift across all three clients and the shared backend.

## ADR-002 — Client state, storage and offline behaviour

**Date:** 2026-11-06
**Status:** Accepted

Flutter with Riverpod is the client architecture. Drift will own the local data model, backed by SQLCipher where supported by the selected platform build. Sensitive offline fields (phone, address, notes and tokens) are additionally protected by an application-managed key held in secure platform storage; no raw database or token is written to logs.

Every locally created or edited record receives a UUID, `client_updated_at`, sync state and immutable outbox operation. The server accepts idempotency keys and returns canonical revisions. The client is usable offline for tract browsing, new-decision capture, assigned follow-up completion and queued sharing analytics. Server-authoritative permissions, assignments, merge operations and destructive privacy actions are reconciled safely once connected.

**Why:** offline-first is a core pilot risk; an online-only form would lose the harvest in poor-network areas.

## ADR-003 — Backend, PostgreSQL and hierarchy enforcement

**Date:** 2026-11-06
**Status:** Accepted

NestJS + TypeScript, PostgreSQL and the `ltree` extension are retained as specified. The application API uses a dedicated least-privilege database role and sets a validated per-request security context inside a transaction. PostgreSQL row-level security is enabled for protected tables; service code also scopes every query. Neither is treated as sufficient by itself.

`org_units` holds `COUNTRY > REGION > PROVINCE > ZONE > AREA > PARISH`, names, codes, active state, parent and `ltree` path. A migration installs database constraints/triggers that reject invalid parent types and cyclic moves. A single transactional move procedure rebuilds the moved subtree path and writes an immutable audit event. Paths use stable UUID-derived labels, not human-readable names or mutable codes.

Read scope is the actor's home unit plus descendants. Global administrators have a null `home_unit_id` and an explicit global role; no other null home unit is valid. A user has exactly one home unit and may have one or more roles, each bounded by that home unit. Parish-level restricted workers see only their assigned converts unless a pastor-created access grant widens that scope.

## ADR-004 — Convert ownership and roll-ups

**Date:** 2026-11-06
**Status:** Accepted

A convert is created at exactly one `registered_at_unit_id` with `registered_by`; `parish_id` is nullable. Records created above parish level without a parish remain in that registering unit's Unassigned Pool. Their age counter begins at creation and they remain eligible for neglected reporting until assignment. Parish assignment is audited and activates the parish follow-up plan.

Roll-ups count a convert once per reporting unit, never once for each arbitrary relationship. They are computed from the current registered/assigned scope using indexed paths and incrementally refreshed unit/day summary tables. The reporting implementation must prove, with tests, that a parish convert appears once in the parish and once in every ancestor total, never double-counted within any total.

Any convert detail read by a non-parish actor creates an append-only audit event. The audit trail uses chained HMAC hashes plus database permissions so ordinary API roles cannot alter history. The implementation must include verification tooling.

## ADR-005 — Privacy, consent and deletion

**Date:** 2026-11-06
**Status:** Accepted

No convert record is persisted without affirmative consent. The capture includes consent version, timestamp, actor, method and notice locale. Phone and address are envelope-encrypted before database persistence; normalized, privacy-preserving lookup values are used only for duplicate detection under a rotation plan. Plain PII is never placed in events, exports, analytics, error reports or audit metadata.

The system will support access/export, correction, removal request, deletion/anonymisation, retention controls and legal-hold policy. A removal request immediately limits routine access while an authorised privacy workflow completes it. The compliance target is the Nigeria Data Protection Act / applicable NDPR guidance and GDPR where applicable; legal counsel must approve final notices, retention periods and data-processing agreements before a real-user pilot.

`mask_phone_numbers_above_parish` defaults to `false` as specified. It is a tenant setting enforced by API serializers/export services, not a client display preference, so it can be switched without an app release.

## ADR-006 — Auth and safety defaults

**Date:** 2026-11-06
**Status:** Accepted

Authentication is phone or email OTP. Public self-service registration is disabled: an approved invitation or administrator-created identity is required. OTP endpoints are rate-limited by identity, IP and device signal; five failed verification attempts trigger a 15-minute lockout by default. Access JWTs are 15 minutes and refresh tokens are rotating, hashed, device/session-bound and remotely revocable. A client-side optional PIN/biometric lock protects an unlocked device.

All traffic requires TLS in deployment. Input schemas are validated server-side, responses use allowlisted DTOs, CORS is allowlisted, security headers are set, and dependency/vulnerability checks run in CI.

## ADR-007 — Follow-up schedule, escalation and messages

**Date:** 2026-11-06
**Status:** Accepted

Default milestones are call within 24 hours, prayer on Day 3, visit on Day 7, then weekly. The schedule is versioned/configurable by authorised church policy, so changing it does not retroactively erase historical expectations. A server-side idempotent worker creates and escalates due tasks; clients can display reminders but are never the sole scheduler.

Firebase Cloud Messaging is the first notification channel. Windows uses local notifications from synced assignments. SMS and WhatsApp providers remain disabled until a church-owned provider account, approved template/consent workflow and monthly hard cap are configured. The default cap is zero, which prevents accidental billable sends.

## ADR-008 — Parish suggestion and assignment safety

**Date:** 2026-11-06
**Status:** Accepted

The app may suggest nearby active parishes only after explicit location permission or an address supplied by the convert. It presents the basis of the suggestion and requires a worker confirmation; it never silently routes a person. When no location is available or confidence is low, the convert remains unassigned at the registering unit for accountable manual allocation.

## ADR-009 — Branding and accessibility

**Date:** 2026-11-06
**Status:** Accepted

`logo.jpg` is the RCCG logo used for the application launcher, splash and in-app brand. `logo-source.png` (INFOFLEX) is restricted to the About/Built-by screen, installer and administrative footer. The `soulwinning.png` flowchart is a requirements artifact, not an in-product graphic.

The visual language will favour the familiar WhatsApp-like model: clear single-purpose screens, large touch targets, plain language, low-data media controls, high contrast and keyboard/screen-reader support. Initial UI locales are English, Yoruba, Hausa, Igbo, French and Nigerian Pidgin, with strings/content delivered from extensible locale catalogs rather than code branches.

## ADR-010 — Releases, signing and platform constraints

**Date:** 2026-11-06
**Status:** Accepted

Release automation will create Android APK/AAB on Linux, iOS archive/IPA on a macOS GitHub Actions runner, and a signed Windows installer plus portable folder on a Windows runner. Signing material is supplied only through church-owned GitHub/environment secret stores and never committed.

This Linux workspace can test shared/backend code and may produce unsigned Android artifacts if the Android SDK is installed. It cannot truthfully produce an Apple-signed IPA/App Store archive without a macOS runner, Xcode and Apple Developer signing assets, nor a Windows installer executable without a Windows runner/toolchain. These constraints will be recorded in each release manifest.

## ADR-011 — Initial deployment posture

**Date:** 2026-11-06
**Status:** Accepted

Use Docker images, a managed PostgreSQL service with encrypted storage, daily backups, point-in-time recovery where offered, and a documented quarterly restore drill. Production has separate application/database roles, no public database endpoint, monitoring/alerting, migration-only schema changes and church-owned cloud/domain/accounts. A single-country pilot is isolated from production global rollout through environments, not separate forks.

## ADR-012 — Phase 0 sponsor confirmations

**Date:** 2026-11-06
**Status:** Accepted

The sponsor confirmed the following Phase 0 operating decisions:

- Use church-owned AWS accounts for the hosting path; no numerical pilot/production budget ceiling was supplied in the response, so spend-cap-dependent production provisioning remains blocked until governance sets one.
- Church IT / Directorate holds the Apple Developer and Google Play Console accounts. Store access and recovery details must remain church-owned.
- A church-owned OV/EV Windows code-signing certificate is available for the eventual `GoYe-Setup.exe` release. It must be injected through CI secret storage only.
- The authoritative country-to-parish hierarchy list will be supplied for import; sample operational hierarchy data must not be treated as canonical.
- Confirm the initial configurable policy: call within 24 hours, prayer on Day 3, visit on Day 7, then weekly; stages are New Convert → Believers’ Class → Baptismal Class → Baptised → Parish Integration (Fully Planted).
- Approve the supplied RCCG `logo.jpg` for the application icon and splash. INFOFLEX `logo-source.png` remains restricted to About/Built-by, installer and administrative footer contexts.

## ADR-013 — Hierarchy bulk import and documentation boundary

**Date:** 2026-11-06
**Status:** Accepted

Hierarchy imports are an explicitly authorised, server-side operational action: files are validated as CSV/XLSX/XLSM before one transactional upsert, parent changes use the controlled database move function, and the applied import is audit-recorded. The development Nigeria/Ghana data is blocked by `ALLOW_SAMPLE_SEED=true`; it is never a substitute for the church's authoritative directory. A dry run requires the schema to be migrated already and rolls back all data work.

Swagger/OpenAPI is published by the API at `/api/docs` and `/api/docs-json` with bearer-token documentation. The document exposes contracts, not database credentials or authority; production deployment may restrict its network reachability.

## ADR-014 — Convert capture consent and encrypted contact fields

**Date:** 2026-11-06
**Status:** Accepted

A convert cannot be persisted unless the request carries affirmative consent and a non-blank policy/notice version. The server—not the client—records the consent timestamp and authenticated actor, and database triggers make the registration origin and captured consent immutable. The service also checks consent itself, so direct service use cannot rely only on HTTP DTO validation.

Names, phone numbers and addresses are encrypted at the API boundary with an authenticated AES-256-GCM envelope using the church-owned `PII_ENCRYPTION_KEY`; raw PII is neither placed in audit metadata nor in reporting fields. An authorised non-Global actor registers only at their own home unit. A Global Admin must explicitly name the registration unit. Above-parish records begin without a parish assignment and are handled by the next workflow task.

## ADR-015 — Unassigned Pool and parish follow-up start

**Date:** 2026-11-06
**Status:** Accepted

A registration at Country through Area is unassigned until an authorised actor selects an active descendant Parish. The pool age is calculated from the immutable server `created_at` at query time, preventing stale counters. A Parish registration is assigned to that same Parish in the capture transaction and therefore never waits in the pool.

Assignment is a one-time controlled database operation: it cannot cross the registration unit boundary, cannot target an inactive/non-Parish unit, and creates exactly one pending Call-24h, Prayer-Day-3, and Visit-Day-7 task. Reassignment is intentionally deferred until a future accountable transfer workflow is designed, rather than silently duplicating follow-up tasks.
