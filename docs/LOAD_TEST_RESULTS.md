# Admin roll-up load test results

**Run date:** 2026-11-06 (UTC)

**Code:** `backend/src/scripts/load-test-admin-rollups.ts` at Task 2.8

**Dataset:** 1,000,000 synthetic, consent-shaped converts; no real church or convert data

## Result

The trigger-maintained `convert_rollup_daily` summary was populated from one million generated converts distributed across two countries, their complete Country → Parish hierarchies, thirty registration dates and all five current stages. The run validated that the country totals summed to the grand total before timing.

| Measure                                   |                                         Value |
| ----------------------------------------- | --------------------------------------------: |
| Seeded converts                           |                                     1,000,000 |
| Seed duration                             |              888,972.53 ms (14 min 48.97 sec) |
| Grand total                               |                                     1,000,000 |
| First-country total                       |                                       666,667 |
| Sum of first-country Region totals        |                                       666,667 |
| Samples per endpoint after three warm-ups |                                            20 |
| Target                                    |                            p95 under 1,000 ms |
| Target outcome                            | **Passed for all measured summary endpoints** |

| Global Admin summary operation | Min (ms) | P50 (ms) | P95 (ms) | Max (ms) |
| ------------------------------ | -------: | -------: | -------: | -------: |
| All-country totals             |     2.37 |     2.99 |     3.50 |     3.59 |
| Selected-country Region totals |     4.40 |     4.95 |     5.96 |     7.87 |
| Selected-country total         |     2.27 |     2.51 |     3.51 |     3.91 |
| Grand total                    |     2.49 |     2.64 |     3.56 |     4.63 |

## Method and interpretation

The run used a fresh `embedded-postgres` PostgreSQL instance in this Linux sandbox, a single local database process and a warm local connection. It called the real `AdminReportsService` methods, which create the normal RLS transaction and query the indexed summary table; the timings therefore include database/RLS/service work but not external network, TLS, reverse proxy or HTTP serialization latency. The P95 target is met in this controlled environment, not claimed as a production capacity guarantee.

The seed intentionally uses structurally valid placeholder encrypted byte buffers because the measured operations are summary-only and never decrypt records. The independent PostgreSQL service/integration suite covers authorised decryption and Country-to-Convert drill-down behavior. A production-like test must be repeated on the church-approved managed PostgreSQL version, hardware, connection pool and network topology before setting a user-facing SLO.

## How to rerun safely

1. Create and migrate an **isolated empty PostgreSQL database**. The runner refuses any database that already contains converts.
2. Set church-owned `DATABASE_URL`, `AUDIT_CHAIN_SECRET` and `PII_ENCRYPTION_KEY` values, then run:

   ```bash
   cd backend
   ALLOW_LOAD_TEST=true npm run load-test:admin-rollups
   ```

3. The default is exactly one million converts, 10,000-row seed batches, three warm-ups and twenty samples. `LOAD_TEST_BATCH_SIZE`, `LOAD_TEST_SAMPLES` and `LOAD_TEST_LABEL` are configurable. `LOAD_TEST_CONVERTS` is available only for a small smoke run; retain the default for the Phase 2 gate.

The runner is intentionally destructive only to the isolated target database. It does not use production data, and it never runs unless `ALLOW_LOAD_TEST=true` is explicitly supplied.
