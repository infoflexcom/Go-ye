# Go-Ye

Go-Ye is RCCG's secure, offline-first soul-winning, convert follow-up and reporting platform. One Flutter application will serve Android, iOS and Windows against one NestJS/PostgreSQL backend.

## Phase 0 — clean skeleton

This repository now contains the safe starting skeleton only. It has no identity data, church hierarchy, converts, user accounts or schema migrations yet.

```text
app/       Flutter/Riverpod client source and platform bootstrap
backend/   NestJS TypeScript API, health endpoint and Jest tests
infra/     Docker development infrastructure
assets/    Exact supplied proposal, flowchart and brand sources
docs/      Architecture, decisions, ERD, progress and engineering guidance
```

## Quick start

```bash
cp .env.example .env
npm install
docker compose up --build
curl --fail http://localhost:3000/api/v1/hello
```

Expected response:

```json
{ "message": "Go-Ye API is ready.", "service": "go-ye-api" }
```

For Flutter setup and Android/Windows launch instructions, see [`app/README.md`](app/README.md). For all prerequisites, quality commands and platform constraints, see [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).

## Core documents

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — system design, requirements traceability and delivery gates.
- [`docs/DECISIONS.md`](docs/DECISIONS.md) — append-only decisions and safe defaults.
- [`docs/ERD.md`](docs/ERD.md) — first logical entity relationship model and migration constraints.
- [`docs/PROGRESS.md`](docs/PROGRESS.md) — current phase gate and next work.
- [`infra/README.md`](infra/README.md) — Docker Compose stack instructions.

## Security boundary

Never commit `.env` files, certificates, signing keys, production databases, real convert information or generated release artifacts. Production accounts, cloud resources, certificates and provider credentials must be church-owned.
