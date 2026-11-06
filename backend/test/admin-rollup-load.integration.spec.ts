import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { runAdminRollupLoadTest } from '../src/scripts/load-test-admin-rollups.js';
import type { TestDatabase } from './support/embedded-postgres.js';
import { createTestDatabase } from './support/embedded-postgres.js';

const auditSecret = 'load-runner-audit-secret-which-is-at-least-thirty-two-bytes';
const piiKey = Buffer.alloc(32, 11).toString('base64');

describe('Admin roll-up load test runner', () => {
  let database: TestDatabase;

  beforeAll(async () => {
    database = await createTestDatabase();
  }, 30_000);

  afterAll(async () => {
    await database.close();
  });

  it('seeds a guarded isolated dataset and verifies all summary totals before timing it', async () => {
    const result = await runAdminRollupLoadTest({
      connectionString: database.connectionString,
      auditSecret,
      piiEncryptionKey: piiKey,
      convertCount: 1_000,
      batchSize: 250,
      samples: 2,
      runLabel: 'runner',
    });

    expect(result).toMatchObject({
      seededConverts: 1_000,
      totals: { grand: 1_000, firstCountry: 667, firstCountryRegions: 667 },
    });
    expect(result.timings.countries.samples).toBe(2);
    expect(result.timings.regions.minMilliseconds).toBeGreaterThanOrEqual(0);
    expect(result.timings.countryTotal.minMilliseconds).toBeGreaterThanOrEqual(0);
    expect(result.timings.grandTotal.minMilliseconds).toBeGreaterThanOrEqual(0);
  });
});
