# Development infrastructure

## Local API and PostgreSQL stack

1. Copy the non-production template:
   ```bash
   cp .env.example .env
   ```
2. Replace `POSTGRES_PASSWORD` and the password in `DATABASE_URL` with the same strong local-only value.
3. Start the stack:
   ```bash
   docker compose up --build
   ```
4. Verify the API in another terminal:
   ```bash
   curl --fail http://localhost:3000/api/v1/hello
   curl --fail http://localhost:3000/api/v1/health
   ```

Expected hello response:

```json
{ "message": "Go-Ye API is ready.", "service": "go-ye-api" }
```

The database is available at `localhost:${POSTGRES_PORT:-5432}` only for local development. The named volume `goye_postgres_data` persists developer data; reset it only with `docker compose down -v` after confirming no desired local test data remains.

## Database-change policy

No application schema is created in Phase 0. Every schema change from Phase 1 onward must be a versioned migration with its rollback note documented beside the migration. Production migration permissions will be separate from API runtime permissions.
