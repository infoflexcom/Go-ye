# Go-Ye delivery progress

**Last updated:** 2026-11-06 (UTC)
**Active branch:** `arena/9a3f746d-go-ye`

## Current gate

**Phase 2 — convert lifecycle and reporting: COMPLETE (`phase-2-complete`). Phase 1 remains tagged `phase-1-complete`.**

Phase 2 is building the convert lifecycle, accurate hierarchy roll-ups, reporting and privacy workflows. No real convert, church hierarchy, identity, provider or production data has been entered into the repository or its development stack; Nigeria/Ghana records are explicitly guarded sample/test data.

## Phase 2 task record

- [x] **2.1 Consent-backed convert capture:** any authorised hierarchy level can register at its own unit; encrypted contact fields, immutable server-captured consent provenance, origin tracking, scoped read/update, and audit events are covered by genuine PostgreSQL tests.
- [x] **2.2 Unassigned Pool and parish assignment:** above-parish registrations surface with a live age-in-days counter; controlled descendant-parish assignment is one-time, schedules the 24-hour/Day-3/Day-7 plan, and parish-origin registrations are assigned/scheduled immediately.
- [x] **2.3 Duplicate detection and merge:** HMAC-protected E.164 lookup identifies only RLS-visible candidates; controlled merge preserves a canonical record, prevents cross-country/different-parish collisions and excludes the duplicate from the pool/counts.
- [x] **2.4 Stage pipeline and append-only timeline:** server-enforced New Convert → Believers’ Class → Baptismal Class → Baptised → Fully Planted transitions require parish assignment and advance one step only; encrypted activity notes/events are append-only and sequence ordered.
- [x] **2.5 Hierarchy roll-ups and summaries:** trigger-maintained daily current-stage summaries attribute each active convert to its parish when assigned (otherwise registration unit) and every ancestor exactly once; genuine PostgreSQL seeded-data tests prove Parish through Country counts and merged-record exclusion.
- [x] **2.6 Global Admin reporting/drill-down:** authenticated Global Admin-only country list, selected-country Region totals, country and grand totals, plus encrypted Country-to-Convert drill-down are backed by roll-up summaries or indexed hierarchy queries. Registration-date/current-stage filters and drill-down pagination are validated through genuine PostgreSQL service and authenticated HTTP tests; every drill-down is tamper-evidently audited.
- [x] **2.7 Removal requests and above-parish read audit:** a scoped worker can submit an encrypted-reason removal request that immediately quarantines the convert from routine detail access, tasks, drill-down and roll-ups. A scoped Privacy Officer (or Global Admin acting in the privacy workflow) can reject or irreversibly anonymise it; encrypted PII/lookup data are removed, pending follow-up is cancelled and all request/resolution and above-parish detail reads are tamper-evidently audited. The Global Admin can toggle the server-enforced `mask_phone_numbers_above_parish` setting (default OFF) without an app release; it masks detail and drill-down phone fields while Parish reads remain unmasked.
- [x] **2.8 One-million-convert load verification:** the isolated genuine PostgreSQL run seeded 1,000,000 synthetic converts in 14m 48.97s, reconciled Country/Region/grand totals, and measured 20 warm local Global Admin summary samples per operation. P95 ranged from 3.50ms to 5.96ms, below the one-second target; see `docs/LOAD_TEST_RESULTS.md`.

## Phase 1 task record

- [x] **1.1 Schema and migrations:** versioned PostgreSQL migrations create the `ltree` hierarchy, users, roles, devices, sessions and append-only audit foundation. Embedded PostgreSQL integration tests verify extensions, hierarchy structure and path construction.
- [x] **1.2 OTP authentication, JWT, refresh and lockout:** OTP challenges are hashed and rate-limited; verification creates device-bound rotating sessions and short-lived JWTs; refresh reuse remotely revokes active sessions.
- [x] **1.3 RBAC and PostgreSQL RLS:** request actors are derived from fresh active sessions and roles; the runtime database role is non-superuser/non-BYPASSRLS; PostgreSQL policies enforce home-unit-plus-descendant scope.
- [x] **1.4 Admin unit/user/role APIs and audited moves:** Global Admin endpoints create/edit/deactivate/move units and manage users/roles; moves rebuild descendant paths transactionally and append tamper-evident audit entries.
- [x] **1.5 Sample seed and hierarchy importer:** guarded sample seed supplies Nigeria and Ghana fixtures; CSV/XLSX import validates, dry-runs, upserts and uses the managed move function where needed.
- [x] **1.6 Permission test matrix and coverage gate:** HTTP-level authenticated PostgreSQL/RLS matrix proves parish isolation, upper-level descendant scope, Global Admin visibility, explicit role 403 and scoped ID-guess 404; auth/authorization coverage is enforced at ≥80% statements/functions/lines.
- [x] **1.7 Swagger publication and hierarchy/permissions documentation:** Swagger UI/OpenAPI JSON are published at `/api/docs` and `/api/docs-json`; hierarchy, RLS, import and role operational documentation is complete.

## Exit criteria record

- [x] Monorepo has `/backend`, `/app`, `/docs`, `/infra` and `/assets`; all four supplied files were copied byte-for-byte into `/assets`.
- [~] Docker Compose API/PostgreSQL stack and hello API smoke path are implemented. The API was verified locally outside Docker; this workspace has no Docker executable, so `docker compose up` could not be run here. A Compose smoke-test CI job is included.
- [x] Backend Prettier, type-aware ESLint, Vitest unit/e2e tests and TypeScript build are configured and pass locally.
- [~] Flutter/Riverpod shell, Dart formatting, analysis, widget tests and Android/iOS/Windows runner bootstrap are configured. This workspace has no Flutter/Dart, Android SDK, Java or Windows toolchain, so Android-emulator and Windows launch commands could not be executed locally.
- [~] CI workflow is committed for backend quality/tests/dependency scan, Docker Compose smoke test, Flutter checks and Android debug build; manual macOS/iOS and Windows builds are scaffolded. GitHub Actions could not be dispatched from this branch because the GitHub integration reports no available workflows and denies Actions permission (`HTTP 403 Resource not accessible by integration`).
- [x] `ARCHITECTURE.md`, `DECISIONS.md`, `PROGRESS.md`, `DEVELOPMENT.md` and the initial logical `ERD.md` exist.
- [x] The six required sponsor questions were sent together and all six responses were received.
- [x] Sponsor confirmations recorded in `docs/DECISIONS.md` (ADR-012).
- [x] Phase 1 permission matrix is 100% green: parish isolation, Area and all upper-level descendants, Global Admin visibility, role-denial `403`, and scoped ID-guess `404` are exercised through authenticated HTTP APIs and genuine PostgreSQL RLS.
- [x] Auth/authorization coverage gate passes: **86.29% statements**, **84.21% functions**, and **86.22% lines** (threshold: 80% each).
- [x] A controlled unit move test proves an Area and its Parish descendant both receive rebuilt `ltree` paths and an audit event.
- [x] Swagger UI and OpenAPI JSON are published and live-smoke-verified at `/api/docs` and `/api/docs-json` (OpenAPI 3.0.0, 15 paths, bearer scheme).
- [x] Annotated Git tag `phase-0-complete` is retained and `phase-1-complete` is created after final validation.

## Completed in this increment

- Re-read the supplied `proposal.docx` and reviewed the `soulwinning.png` flowchart before coding.
- Created the requested monorepo directory layout and copied all four supplied files into `assets/`.
- Created the NestJS hello/health API, PostgreSQL Compose stack, local environment template, Dockerfile and API unit/e2e test setup.
- Created the Flutter/Riverpod shell, widget test, lint configuration and reproducible Android/iOS/Windows runner bootstrap script.
- Added Prettier, type-aware ESLint, Dart/Flutter formatting and analysis commands, and Husky/lint-staged pre-commit configuration.
- Added CI jobs for backend, Docker Compose smoke test, Flutter tests and Android debug build, plus manually dispatched macOS/iOS and Windows build scaffolds.
- Added the first logical ERD and Phase 0 developer-operating instructions.
- Added versioned PostgreSQL identity/hierarchy/audit/RLS migrations, OTP sessions, rotating refresh tokens and runtime database roles.
- Added Global Admin reporting endpoints: all-country totals, selected-country Region totals, selected-country totals, a grand total, and paginated Country-to-Convert detail with encrypted PII decrypted only after authorisation.
- Added stage and registration-date filters to each Global Admin report, used current-stage roll-up summaries for totals, and audited every above-parish convert drill-down read without PII in the audit metadata.
- Added a removal-request privacy workflow with database-enforced request quarantine, authorised reject/anonymise resolution, cancellation of pending follow-up, encrypted request/resolution notes and roll-up removal/reinstatement rules.
- Added audit coverage for above-Parish detail, duplicate-candidate, timeline and Unassigned Pool reads; Privacy Officer/Global Admin resolution and above-parish reads retain no PII in audit metadata.
- Added a guarded Admin roll-up load-test runner and completed an isolated genuine PostgreSQL one-million-convert run. All four measured Global Admin summary operations met the under-one-second P95 target; exact methodology and numbers are in `docs/LOAD_TEST_RESULTS.md`.
- Added a database-backed `mask_phone_numbers_above_parish` tenant setting, defaulting to OFF. Global Admin can change it via the authenticated privacy settings API; serializers mask above-Parish detail and report phones at request time, with tests covering default, toggle, Parish exception and report drill-down enforcement.
- Extended genuine PostgreSQL and authenticated HTTP coverage to prove country/Region/grand totals, merged-record exclusion, filters, pagination, Global Admin-only access and drill-down audit creation.
- Added audited Global Admin hierarchy/user/role APIs and atomic descendant-path rebuilding moves.
- Added guarded Nigeria/Ghana sample seed data plus validated CSV/XLSX/XLSM hierarchy import/dry-run tooling.
- Added authenticated HTTP permission matrix coverage with a genuine PostgreSQL `ltree`/RLS database and an enforced auth/authorization coverage gate.
- Published Swagger/OpenAPI and documented hierarchy, RLS, imports, role semantics and operational constraints.

## Validation record

| Check                                                        | Result                                                                                                                                        |
| ------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `npm run backend:format:check`                               | Passed                                                                                                                                        |
| `npm run backend:lint`                                       | Passed                                                                                                                                        |
| `npm run backend:test`                                       | Passed — 11 files, 38 tests (including load-runner, authenticated privacy workflow, Global Admin reporting, HTTP/RLS and PostgreSQL coverage) |
| `npm run backend:build`                                      | Passed                                                                                                                                        |
| `npm audit --omit=dev --audit-level=high`                    | Passed — no high/critical production findings; see known issues for 2 moderate `exceljs`/`uuid` findings                                      |
| `python3 scripts/validate_foundation.py`                     | Passed                                                                                                                                        |
| `npx prettier --check .`                                     | Passed                                                                                                                                        |
| `git diff --check`                                           | Passed                                                                                                                                        |
| Local compiled API `GET /api/v1/hello`                       | Passed — returned documented response                                                                                                         |
| Local compiled API `GET /api/v1/health`                      | Passed — API healthy; database intentionally not configured outside Compose                                                                   |
| Supplied asset copy SHA-256 comparison                       | Passed — four source/copy pairs match                                                                                                         |
| `npm --workspace=@goye/backend run test:coverage`            | Passed — auth/authorization: 86.29% statements, 84.21% functions, 86.22% lines (all ≥80%)                                                     |
| Live compiled Swagger smoke                                  | Passed — `/api/docs` returned 200; `/api/docs-json` returned OpenAPI 3.0.0, 15 paths and bearer security                                      |
| Docker Compose / Flutter / Android emulator / Windows launch | Not runnable in this workspace; CI configuration is present, but remote Actions dispatch is currently not authorised for this integration     |

## Sponsor confirmations received

- **Hosting:** church-owned AWS; numerical budget ceiling was not supplied and remains a production-provisioning gate.
- **Store accounts:** Church IT / Directorate holds Apple Developer and Google Play Console accounts.
- **Windows signing:** church-owned OV/EV certificate is available.
- **Hierarchy:** the authoritative list will be supplied; no canonical sample data is authorised.
- **Journey policy:** default schedule and five stage names are confirmed.
- **RCCG logo:** approved for the Go-Ye app icon and splash.

## Scope deferred to Phase 2 and later

- Versioned PostgreSQL `ltree` migrations, rollback notes, RLS policies and tamper-evident audit implementation.
- Authentication/OTP, session security, role assignments, church hierarchy import and global-admin bootstrap.
- Encrypted local Drift/SQLCipher storage, offline sync protocol and encrypted PII.
- Convert journey, Unassigned Pool, duplicate handling, follow-up scheduling/escalation, content sharing, reports and notifications.
- Production cloud provisioning, provider accounts, signing, release packages, security review and pilot data collection.

## Known issues and approval boundary

- `npm audit --omit=dev --audit-level=high` passes, but reports **two moderate production advisories** through `exceljs@4.4.0` → `uuid@8.3.2` (GHSA-w5hq-g745-h8pq). `npm audit fix --force` proposes a breaking downgrade to `exceljs@3.4.0`; it was not applied blindly. Before production deployment, replace or upgrade the spreadsheet library after compatibility/security review, then rerun import tests and the audit.
- Full development dependency audit also has tooling advisories; production runtime is gated on the production-only high/critical scan above. CI and release governance must continue to review fresh audit output.
- Actual church hierarchy data, cloud deployment, provider credentials, mobile/desktop builds and real convert records remain excluded from this development repository. All numbered Phase 2 tasks and the server-enforced phone-masking policy are implemented and verified; Phase 2 is tagged `phase-2-complete` after the final clean validation pass.

## Known platform constraints

This Phase 0 workspace is Linux and lacks Docker Engine, Flutter/Dart, Java, Android SDK, macOS/Xcode and Windows toolchains. It therefore cannot truthfully demonstrate Compose startup, Android emulator launch, Windows launch, APK/AAB, IPA/archive or EXE creation locally. The Compose configuration, Flutter runner bootstrap and CI workflows have been prepared. Actual runner verification needs an authorised GitHub Actions run or the relevant local platform/toolchain.
