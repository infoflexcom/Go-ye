# Go-Ye delivery progress

**Last updated:** 2026-11-06 (UTC)
**Active branch:** `arena/9a3f746d-go-ye`

## Current gate

**Phase 0 — Foundation and architecture: COMPLETE; awaiting sponsor approval.**

No source application or schema migration has been created yet. This is intentional: the system's hierarchy, consent, privacy, offline and release constraints were first documented so that implementation starts from an approved, testable safety baseline.

## Completed in this increment

- Read the supplied `proposal.docx` in full.
- Reviewed `soulwinning.png` flowchart, RCCG `logo.jpg` and INFOFLEX `logo-source.png` usage requirements.
- Established an append-only decision log for architecture, offline storage, hierarchy/RLS, consent/privacy, auth, notifications, branding and platform builds.
- Defined delivery phases, functional traceability, logical model, security controls, test evidence and actual build limitations in `docs/ARCHITECTURE.md`.
- Added `.env.example` with non-secret placeholders only and `.gitignore` protection for local secrets, signing material and build artifacts.
- Confirmed no untracked secret or generated production artifact was introduced.
- Ran `python3 scripts/validate_foundation.py` (pass) and `git diff --check` (pass) to guard the required documentation and secret-hygiene baseline.

## Scope explicitly deferred to Phase 1

- NestJS, Flutter and Docker project scaffolding.
- Versioned PostgreSQL `ltree` migrations and rollback notes.
- RLS policies, audit chain implementation, API health endpoint and OpenAPI contract.
- Test runner setup and CI workflows.
- Any identity, convert, parish or other production/pilot data.

## Approval required

Approve **Phase 1 — Secure platform foundation** to begin the scaffold, database migrations, hierarchy/RLS/audit primitives, authentication foundation, automated tests and CI. Decisions that will need church input before Phase 2 stores real data are listed below; safe defaults are already logged in `docs/DECISIONS.md`.

1. Church-owned production cloud, domain, Android/Apple/Windows signing identities and Firebase project.
2. Legal approval of the privacy notice, retention schedule, data-processing arrangements and deletion workflow.
3. Initial Global Admin governance and the authoritative first country/region/parish directory.
4. Approved SMS/WhatsApp vendors, budget cap and message templates (both integrations remain off until then).
5. Pilot parishes, pastoral champions, training plan and support/escalation contacts.

## Known platform constraints

This repository is currently worked from Linux. No signed Android, iOS or Windows deliverable exists at this point. iOS release artifacts need macOS, Xcode and Apple Developer signing assets; Windows installer artifacts need a Windows runner/toolchain; all release signing credentials must reside in church-owned CI secret storage.
