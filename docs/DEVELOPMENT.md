# Go-Ye development and quality guide

## Prerequisites

- Node.js 22+ and npm 10+
- Docker Engine with Docker Compose v2 for the API/database stack
- A current stable Flutter SDK, Java 17 and Android SDK for Android development
- Visual Studio 2022 with Desktop development with C++ for Windows development
- macOS/Xcode only for iOS build/archive work

## One-time setup

```bash
cp .env.example .env
npm install
cd app && ./tool/bootstrap_platforms.sh && flutter pub get
```

`.env` is local-only and intentionally ignored. Use only disposable development database values. Do not place church/provider/certificate secrets in this repository.

## Run the development stack

```bash
docker compose up --build
curl --fail http://localhost:3000/api/v1/hello
curl --fail http://localhost:3000/api/v1/health
```

The API Swagger UI is available at `http://localhost:3000/api/docs`.

## Run quality checks

```bash
npm run backend:format:check
npm run backend:lint
npm run backend:test
npm --workspace=@goye/backend run test:coverage
npm run backend:build
python3 scripts/validate_foundation.py

cd app
flutter analyze
flutter test
flutter run
```

## Formatting and pre-commit hooks

- JavaScript/TypeScript/Markdown/YAML/JSON use Prettier.
- Backend TypeScript uses ESLint plus type-aware `@typescript-eslint` rules.
- Flutter/Dart uses `dart format`, `flutter analyze` and `flutter test`.
- `npm install` enables Husky. The pre-commit hook invokes `lint-staged`; it formats staged eligible files and runs ESLint fixes for staged backend TypeScript.

Run `npm run format` before committing a broad change. Any generated release package, signing key, `.env`, local database or real convert data must remain untracked.

## Platform build boundaries

The Linux workspace used for this phase has no Docker executable, Flutter SDK, Android SDK, Java or Windows/macOS build tools. The commands and CI workflow are provided but were not falsely claimed as locally executed. The Android CI job builds an unsigned debug APK; iOS and Windows scaffold jobs are manual `workflow_dispatch` jobs until church-owned signing assets and release governance are supplied.

## Hierarchy operations (Phase 1)

Read [HIERARCHY_AND_PERMISSIONS.md](HIERARCHY_AND_PERMISSIONS.md) before changing the church directory. Run database migrations before any import. A validated, rollback-only preview is available with:

```bash
npm run hierarchy:import --workspace=@goye/backend -- --file ./hierarchy.xlsx --dry-run
```

The Nigeria/Ghana sample is strictly development-only and requires `ALLOW_SAMPLE_SEED=true`; never use it with real church records. Swagger UI is served at `/api/docs`, with machine-readable OpenAPI at `/api/docs-json`.
