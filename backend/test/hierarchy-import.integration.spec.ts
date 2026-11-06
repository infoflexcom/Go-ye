import ExcelJS from 'exceljs';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  applyHierarchyImport,
  normalizeHierarchyRows,
  readHierarchyFile,
  sortHierarchyRows,
} from '../src/hierarchy/hierarchy-import.js';
import { beginSystemTransaction } from '../src/scripts/database-script.util.js';
import type { TestDatabase } from './support/embedded-postgres.js';
import { createTestDatabase } from './support/embedded-postgres.js';

const auditSecret = 'import-test-audit-secret-which-is-at-least-thirty-two-bytes';

describe('hierarchy import tools', () => {
  let database: TestDatabase;

  beforeAll(async () => {
    database = await createTestDatabase();
  }, 30_000);

  afterAll(async () => {
    await database.close();
  });

  it('reads the documented CSV template and creates Nigeria plus a second country idempotently', async () => {
    const rows = await readHierarchyFile(join(process.cwd(), 'test/fixtures/sample-hierarchy.csv'));
    expect(rows).toHaveLength(12);
    const client = await database.pool.connect();
    try {
      await beginSystemTransaction(client, auditSecret);
      await expect(applyHierarchyImport(client, rows)).resolves.toEqual({
        created: 12,
        updated: 0,
        moved: 0,
      });
      await client.query('COMMIT');

      await beginSystemTransaction(client, auditSecret);
      await expect(applyHierarchyImport(client, rows)).resolves.toEqual({
        created: 0,
        updated: 12,
        moved: 0,
      });
      await client.query('COMMIT');
    } finally {
      client.release();
    }

    const countries = await database.pool.query<{ code: string }>(
      "SELECT code FROM org_units WHERE type = 'COUNTRY' ORDER BY code",
    );
    expect(countries.rows.map((row) => row.code)).toEqual(['GH', 'NG']);
  });

  it('accepts an Excel template and rejects malformed ordering or parent types before persistence', async () => {
    const directory = await mkdtemp(join(tmpdir(), 'goye-import-'));
    const file = join(directory, 'template.xlsx');
    try {
      const workbook = new ExcelJS.Workbook();
      const sheet = workbook.addWorksheet('Hierarchy');
      sheet.addRow(['type', 'name', 'code', 'parent_code', 'is_active']);
      sheet.addRow(['COUNTRY', 'Benin', 'BJ', '', 'true']);
      await workbook.xlsx.writeFile(file);
      await expect(readHierarchyFile(file)).resolves.toEqual([
        { type: 'COUNTRY', name: 'Benin', code: 'BJ', parentCode: undefined, isActive: true },
      ]);
    } finally {
      await rm(directory, { recursive: true, force: true });
    }

    const malformed = normalizeHierarchyRows([
      { type: 'COUNTRY', name: 'Nigeria', code: 'NG', parent_code: '', is_active: 'true' },
      { type: 'PROVINCE', name: 'Bad Province', code: 'BAD', parent_code: 'NG', is_active: 'true' },
    ]);
    expect(() => sortHierarchyRows(malformed)).toThrow(/invalid COUNTRY parent/i);
  });
});
