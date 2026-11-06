# Go-Ye

Go-Ye is RCCG's offline-first soul-winning, convert follow-up and reporting platform. It is being delivered as a Flutter application for Android, iOS and Windows backed by a single NestJS/PostgreSQL service.

## Delivery status

**Phase 0 — Foundation and architecture is complete and awaiting approval.** No app or backend scaffold exists yet; see [`docs/PROGRESS.md`](docs/PROGRESS.md) for the live gate and [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for requirements traceability, architecture, privacy, security and release approach.

## Key documents

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — system design, user-story traceability and phase plan.
- [`docs/DECISIONS.md`](docs/DECISIONS.md) — safe defaults and architecture decision record.
- [`docs/PROGRESS.md`](docs/PROGRESS.md) — current delivery state and approval gate.
- [`.env.example`](.env.example) — non-secret local configuration template.

## Confidentiality and release safety

Do not commit `.env` files, certificates, signing keys, database dumps, real convert data or generated release artifacts. Production accounts, cloud resources, certificates and provider credentials must be church-owned.

Signed Android, iOS and Windows releases have not been built in this phase. The documented build plan uses Linux, macOS and Windows CI runners respectively when the church-owned signing material is available.
