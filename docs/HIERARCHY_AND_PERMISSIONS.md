# Hierarchy and permissions

Phase 1 establishes the single hierarchy and access boundary for every later module. No client decides scope: the Nest API authenticates the session, derives fresh roles and home unit, then runs the query in a PostgreSQL transaction under the non-superuser `goye_runtime` role. PostgreSQL Row-Level Security (RLS) is forced on protected data.

## Fixed organisation hierarchy

Global Admin is a system role, not a row in the organisation table. Below it, a single `org_units` table enforces this exact parent relationship:

```text
Global Admin
└── COUNTRY
    └── REGION
        └── PROVINCE
            └── ZONE
                └── AREA
                    └── PARISH
```

| Child type | Required parent type |
| ---------- | -------------------- |
| `COUNTRY`  | none                 |
| `REGION`   | `COUNTRY`            |
| `PROVINCE` | `REGION`             |
| `ZONE`     | `PROVINCE`           |
| `AREA`     | `ZONE`               |
| `PARISH`   | `AREA`               |

Each row has a UUID, human-visible unique `code`, name, active state, `parent_id`, and an `ltree` `path`. Path labels are UUID-derived stable labels rather than names or codes, so edits do not invalidate hierarchy paths. Parent/type validation, loop prevention and path derivation are database-enforced. `ltree` indexes support fast descendant lookup and later reporting roll-ups.

### Moving a unit

Only a `GLOBAL_ADMIN` can invoke `POST /api/v1/admin/org-units/:id/move`. The controlled `goye_move_org_unit` database function validates the target parent, rejects cycles, changes the parent, and rebuilds the path for the moved unit and **every** descendant in one transaction. An append-only HMAC-chain audit event is written in the same transaction. Direct ordinary-role path or parent updates are not permitted.

## User homes, roles, and visibility

- A non-Global-Admin active user must have exactly one home unit.
- A Global Admin has `home_unit_id = NULL` and the explicit `GLOBAL_ADMIN` role.
- Users may hold multiple roles, but scope remains their home unit plus descendants.
- A session is checked for active status, revocation and expiry; roles are read freshly from the database rather than trusted from a stale JWT claim.
- The role guard returns `403` when an authenticated user lacks a required role. RLS hides an existing row outside the actor's scope, and the API returns `404` to prevent identifier probing.

The authenticated directory endpoints are intentionally limited, safe examples of this boundary:

- `GET /api/v1/directory/org-units` — actor home unit and descendants only.
- `GET /api/v1/directory/org-units/:id` — one scoped unit, otherwise `404`.
- `GET /api/v1/directory/users/:id` — one scoped user with no contact details, otherwise `404`.

Global administration endpoints under `/api/v1/admin` require `GLOBAL_ADMIN`; their hierarchy and user/role changes are audited. The complete executable matrix is in [PERMISSION_TEST_MATRIX.md](PERMISSION_TEST_MATRIX.md).

## CSV / Excel hierarchy import

Real hierarchy imports accept UTF-8 `.csv`, `.xlsx`, and `.xlsm` workbooks. The first worksheet/CSV row must contain these exact case-insensitive column names:

| Column        | Required    | Rule                                                                                                                                 |
| ------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `type`        | yes         | One of `COUNTRY`, `REGION`, `PROVINCE`, `ZONE`, `AREA`, `PARISH`.                                                                    |
| `name`        | yes         | Non-empty display name.                                                                                                              |
| `code`        | yes         | Unique in the file and database; normalised to upper case.                                                                           |
| `parent_code` | conditional | Blank for a country; required for every other type. May refer to an earlier/later row in the same file or an existing database unit. |
| `is_active`   | yes         | `true`/`false`, `1`/`0`, `yes`/`no`, or `active`/`inactive`.                                                                         |

Rows are validated before persistence, sorted so parents are created before children, and rejected for duplicate codes, invalid parent types, unresolved parents or cycles. Existing rows are updated idempotently by code. If an existing row's parent changes, the importer invokes `goye_move_org_unit`; it never writes a path directly. The whole import is a single transaction.

1. Review the file in a non-production environment and back up production first.
2. Run versioned migrations as the database migration operator: `npm run migration:up --workspace=@goye/backend`.
3. Set `DATABASE_URL` and the church-owned `AUDIT_CHAIN_SECRET`.
4. Validate without importing data:

   ```bash
   npm run hierarchy:import --workspace=@goye/backend -- --file ./hierarchy.xlsx --dry-run
   ```

5. Apply the reviewed file:

   ```bash
   npm run hierarchy:import --workspace=@goye/backend -- --file ./hierarchy.xlsx
   ```

The dry run opens a transaction then rolls it back. It requires already-applied migrations and does not write hierarchy rows or audit entries. Imports are auditable as `HIERARCHY_IMPORTED`.

### Sample data

The development-only sample creates Nigeria (Lagos branch with two parishes) and Ghana (Accra branch), plus a non-real sample Global Admin. It is deliberately blocked unless `ALLOW_SAMPLE_SEED=true` is set:

```bash
npm run migration:up --workspace=@goye/backend
ALLOW_SAMPLE_SEED=true npm run seed:sample --workspace=@goye/backend
```

Do not run it against a database that contains church records. The supplied `backend/test/fixtures/sample-hierarchy.csv` documents the template shape; it is test data, not an authoritative RCCG directory.

## Operational safeguards

- Migration files are versioned and retain paired down migrations; apply them under normal backup/change-control procedures.
- The API application role has no bypass-RLS privilege. `SET LOCAL` actor context is transaction-scoped, limiting connection-pool leakage.
- The security-definer audit append function has a safe search path and no `PUBLIC` execute grant.
- Import/seed scripts require an audit secret and run as the constrained runtime role with the explicit system context.
- Test coverage uses genuine embedded PostgreSQL, including `ltree`, RLS and HTTP requests; it is not a SQL emulator.
