# Phase 1 permission test matrix

`backend/test/permission-matrix.e2e-spec.ts` is a real HTTP test against the Nest API and an ephemeral genuine PostgreSQL instance with `ltree` and forced row-level security. It creates an authenticated session and signed access token for each actor, rather than calling services as a database owner.

| Actor home unit / role         | Expected directory scope          | HTTP proof                                                                                                         |
| ------------------------------ | --------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| Parish Alpha / `PARISH_PASTOR` | The Parish Alpha unit only        | `GET /directory/org-units` returns exactly Parish Alpha. Guessed Ghana unit and Parish Beta user IDs return `404`. |
| Area / `AREA_LEADER`           | Its Area plus both child parishes | Exact three-unit result asserted.                                                                                  |
| Zone / `ZONE_LEADER`           | Zone, Area, both Parishes         | Exact descendant set asserted.                                                                                     |
| Province / `PROVINCE_LEADER`   | Province through both Parishes    | Exact descendant set asserted.                                                                                     |
| Region / `REGION_LEADER`       | Region through both Parishes      | Exact descendant set asserted.                                                                                     |
| Country / `COUNTRY_ADMIN`      | Country through both Parishes     | Exact descendant set asserted.                                                                                     |
| Global Admin / `GLOBAL_ADMIN`  | Nigeria and Ghana branches        | Complete nine-unit result asserted.                                                                                |
| Parish Alpha / `PARISH_PASTOR` | No Global Admin API access        | `GET /admin/org-units/:id` returns `403`.                                                                          |

A scoped row that exists but is outside the actor's RLS visibility deliberately returns `404`, not `403`, so identifiers cannot be confirmed by guessing. Explicit role failure on a Global Admin endpoint deliberately returns `403`.

## Running the gate

```bash
npm run backend:test
npm --workspace=@goye/backend run test:coverage
```

The coverage command is scoped to `src/auth` and `src/authorization` and enforces at least 80% statements, functions, and lines.
