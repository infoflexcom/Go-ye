# Go-Ye delivery progress

**Last updated:** 2026-11-06 (UTC)
**Active branch:** `arena/9a3f746d-go-ye`

## Current gate

**Phase 0 — clean project skeleton: IN PROGRESS.**

This phase creates only the safe engineering foundation. No real convert, church hierarchy, identity, provider or production data may be entered into this repository or its development stack.

## Target exit criteria

- [ ] Monorepo has `/backend`, `/app`, `/docs`, `/infra` and `/assets`; supplied proposal, flowchart and logos are copied into `/assets`.
- [ ] `docker compose up --build` starts PostgreSQL and the API; `GET /api/v1/hello` returns the documented response.
- [ ] Backend linting, formatting, unit/e2e test framework and build are configured.
- [ ] Flutter/Riverpod shell, formatting, analysis and widget-test framework are configured for Android/iOS/Windows bootstrap.
- [ ] GitHub Actions covers backend checks, Flutter checks and Android debug build, with manual macOS/iOS and Windows scaffold build jobs.
- [ ] Architecture, decision log, progress record and initial ERD are present.
- [ ] The six required sponsor questions have been sent in one batch.
- [ ] Checks that this environment can run have passed; unavailable Docker/Flutter/platform checks are transparently recorded.
- [ ] `phase-0-complete` is an annotated Git tag after validation.

## Completed in this increment

- Re-read the supplied `proposal.docx` and reviewed the `soulwinning.png` flowchart before coding.
- Created the requested monorepo directory layout and copied all four supplied files into `assets/`.
- Created the NestJS hello/health API, PostgreSQL Compose stack, local environment template, Dockerfile and API unit/e2e test setup.
- Created the Flutter/Riverpod shell, widget test, lint configuration and reproducible Android/iOS/Windows runner bootstrap script.
- Added Prettier, type-aware ESLint, Dart/Flutter formatting and analysis commands, and Husky/lint-staged pre-commit configuration.
- Added CI jobs for backend, Flutter tests and Android debug build, plus manually dispatched macOS/iOS and Windows build scaffolds.
- Added the first logical ERD and Phase 0 developer-operating instructions.

## Validation record

Pending final command results and tag creation.

## Scope explicitly deferred to Phase 1

- Versioned PostgreSQL `ltree` migrations, rollback notes, RLS policies and tamper-evident audit implementation.
- Authentication/OTP, session security, role assignments, church hierarchy import and global-admin bootstrap.
- Encrypted local Drift/SQLCipher storage, offline sync protocol and encrypted PII.
- Convert journey, Unassigned Pool, duplicate handling, follow-up scheduling/escalation, content sharing, reports and notifications.
- Production cloud provisioning, provider accounts, signing, release packages, security review and pilot data collection.

## Known platform constraints

This Phase 0 workspace is Linux and currently lacks Docker Engine, Flutter/Dart, Java, Android SDK, macOS/Xcode and Windows toolchains. It therefore cannot truthfully demonstrate Compose startup, Android emulator launch, Windows launch, APK/AAB, IPA/archive or EXE creation locally. The Compose configuration, Flutter runner bootstrap and CI workflows have been prepared; actual runner verification belongs to the relevant available platform/CI execution.
