# Go-Ye delivery progress

**Last updated:** 2026-11-06 (UTC)
**Active branch:** `arena/9a3f746d-go-ye`

## Current gate

**Phase 1 — foundation: IN PROGRESS. Phase 0 remains tagged `phase-0-complete`.**

This phase created only the safe engineering foundation. No real convert, church hierarchy, identity, provider or production data has been entered into the repository or its development stack.

## Phase 1 task record

- [x] **1.1 Schema and migrations:** versioned PostgreSQL migrations create the `ltree` hierarchy, users, roles, devices, sessions and append-only audit foundation. Embedded PostgreSQL integration tests verify extensions, hierarchy structure and path construction.
- [x] **1.2 OTP authentication, JWT, refresh and lockout:** OTP challenges are hashed and rate-limited; verification creates device-bound rotating sessions and short-lived JWTs; refresh reuse remotely revokes active sessions.
- [ ] **1.3 RBAC and PostgreSQL RLS**
- [ ] **1.4 Admin unit/user/role APIs and audited moves**
- [ ] **1.5 Sample seed and hierarchy importer**
- [ ] **1.6 Permission test matrix and coverage gate**
- [ ] **1.7 Swagger publication and hierarchy/permissions documentation**

## Exit criteria record

- [x] Monorepo has `/backend`, `/app`, `/docs`, `/infra` and `/assets`; all four supplied files were copied byte-for-byte into `/assets`.
- [~] Docker Compose API/PostgreSQL stack and hello API smoke path are implemented. The API was verified locally outside Docker; this workspace has no Docker executable, so `docker compose up` could not be run here. A Compose smoke-test CI job is included.
- [x] Backend Prettier, type-aware ESLint, Vitest unit/e2e tests and TypeScript build are configured and pass locally.
- [~] Flutter/Riverpod shell, Dart formatting, analysis, widget tests and Android/iOS/Windows runner bootstrap are configured. This workspace has no Flutter/Dart, Android SDK, Java or Windows toolchain, so Android-emulator and Windows launch commands could not be executed locally.
- [~] CI workflow is committed for backend quality/tests/dependency scan, Docker Compose smoke test, Flutter checks and Android debug build; manual macOS/iOS and Windows builds are scaffolded. GitHub Actions could not be dispatched from this branch because the GitHub integration reports no available workflows and denies Actions permission (`HTTP 403 Resource not accessible by integration`).
- [x] `ARCHITECTURE.md`, `DECISIONS.md`, `PROGRESS.md`, `DEVELOPMENT.md` and the initial logical `ERD.md` exist.
- [x] The six required sponsor questions were sent together and all six responses were received.
- [x] Sponsor confirmations recorded in `docs/DECISIONS.md` (ADR-012).
- [x] Annotated Git tag `phase-0-complete` is created after final documentation validation.

## Completed in this increment

- Re-read the supplied `proposal.docx` and reviewed the `soulwinning.png` flowchart before coding.
- Created the requested monorepo directory layout and copied all four supplied files into `assets/`.
- Created the NestJS hello/health API, PostgreSQL Compose stack, local environment template, Dockerfile and API unit/e2e test setup.
- Created the Flutter/Riverpod shell, widget test, lint configuration and reproducible Android/iOS/Windows runner bootstrap script.
- Added Prettier, type-aware ESLint, Dart/Flutter formatting and analysis commands, and Husky/lint-staged pre-commit configuration.
- Added CI jobs for backend, Docker Compose smoke test, Flutter tests and Android debug build, plus manually dispatched macOS/iOS and Windows build scaffolds.
- Added the first logical ERD and Phase 0 developer-operating instructions.

## Validation record

| Check                                                        | Result                                                                                                                                    |
| ------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `npm run backend:format:check`                               | Passed                                                                                                                                    |
| `npm run backend:lint`                                       | Passed                                                                                                                                    |
| `npm run backend:test`                                       | Passed — 2 files, 3 tests                                                                                                                 |
| `npm run backend:build`                                      | Passed                                                                                                                                    |
| `npm audit --omit=dev --audit-level=high`                    | Passed — 0 production vulnerabilities                                                                                                     |
| `python3 scripts/validate_foundation.py`                     | Passed                                                                                                                                    |
| `npx prettier --check .`                                     | Passed                                                                                                                                    |
| `git diff --check`                                           | Passed                                                                                                                                    |
| Local compiled API `GET /api/v1/hello`                       | Passed — returned documented response                                                                                                     |
| Local compiled API `GET /api/v1/health`                      | Passed — API healthy; database intentionally not configured outside Compose                                                               |
| Supplied asset copy SHA-256 comparison                       | Passed — four source/copy pairs match                                                                                                     |
| Docker Compose / Flutter / Android emulator / Windows launch | Not runnable in this workspace; CI configuration is present, but remote Actions dispatch is currently not authorised for this integration |

## Sponsor confirmations received

- **Hosting:** church-owned AWS; numerical budget ceiling was not supplied and remains a production-provisioning gate.
- **Store accounts:** Church IT / Directorate holds Apple Developer and Google Play Console accounts.
- **Windows signing:** church-owned OV/EV certificate is available.
- **Hierarchy:** the authoritative list will be supplied; no canonical sample data is authorised.
- **Journey policy:** default schedule and five stage names are confirmed.
- **RCCG logo:** approved for the Go-Ye app icon and splash.

## Scope deferred to Phase 1

- Versioned PostgreSQL `ltree` migrations, rollback notes, RLS policies and tamper-evident audit implementation.
- Authentication/OTP, session security, role assignments, church hierarchy import and global-admin bootstrap.
- Encrypted local Drift/SQLCipher storage, offline sync protocol and encrypted PII.
- Convert journey, Unassigned Pool, duplicate handling, follow-up scheduling/escalation, content sharing, reports and notifications.
- Production cloud provisioning, provider accounts, signing, release packages, security review and pilot data collection.

## Known platform constraints

This Phase 0 workspace is Linux and lacks Docker Engine, Flutter/Dart, Java, Android SDK, macOS/Xcode and Windows toolchains. It therefore cannot truthfully demonstrate Compose startup, Android emulator launch, Windows launch, APK/AAB, IPA/archive or EXE creation locally. The Compose configuration, Flutter runner bootstrap and CI workflows have been prepared. Actual runner verification needs an authorised GitHub Actions run or the relevant local platform/toolchain.
