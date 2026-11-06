import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { TestDatabase } from './support/embedded-postgres.js';
import { createTestDatabase } from './support/embedded-postgres.js';

describe('0001 core schema migration', () => {
  let database: TestDatabase;

  beforeAll(async () => {
    database = await createTestDatabase();
  }, 30_000);

  afterAll(async () => {
    await database.close();
  });

  it('installs ltree, core tables and the role catalogue', async () => {
    const extensions = await database.pool.query<{ extname: string }>(
      "SELECT extname FROM pg_extension WHERE extname IN ('ltree', 'pgcrypto') ORDER BY extname",
    );
    expect(extensions.rows.map((row) => row.extname)).toEqual(['ltree', 'pgcrypto']);

    const tables = await database.pool.query<{ tablename: string }>(
      `SELECT tablename FROM pg_tables
       WHERE schemaname = 'public'
       AND tablename IN ('roles', 'org_units', 'users', 'user_roles', 'devices', 'sessions', 'audit_log')
       ORDER BY tablename`,
    );
    expect(tables.rows.map((row) => row.tablename)).toEqual([
      'audit_log',
      'devices',
      'org_units',
      'roles',
      'sessions',
      'user_roles',
      'users',
    ]);

    const roles = await database.pool.query<{ key: string }>('SELECT key FROM roles ORDER BY key');
    expect(roles.rows).toHaveLength(11);
    expect(roles.rows.map((role) => role.key)).toContain('GLOBAL_ADMIN');
  });

  it('enforces the six stored unit types beneath the separate Global Admin scope', async () => {
    const country = await database.pool.query<{ id: string; path: string }>(
      `INSERT INTO org_units (type, name, code)
       VALUES ('COUNTRY', 'Nigeria', 'NG')
       RETURNING id, path::text`,
    );
    const region = await database.pool.query<{ id: string; path: string }>(
      `INSERT INTO org_units (type, name, code, parent_id)
       VALUES ('REGION', 'Lagos Region', 'NG-LAG', $1)
       RETURNING id, path::text`,
      [country.rows[0].id],
    );

    expect(region.rows[0].path).toBe(
      `${country.rows[0].path}.u${region.rows[0].id.replaceAll('-', '')}`,
    );

    await expect(
      database.pool.query(
        `INSERT INTO org_units (type, name, code, parent_id)
         VALUES ('PROVINCE', 'Invalid Province', 'NG-BAD', $1)`,
        [country.rows[0].id],
      ),
    ).rejects.toThrow(/invalid parent type/i);

    const otherCountry = await database.pool.query<{ id: string }>(
      `INSERT INTO org_units (type, name, code)
       VALUES ('COUNTRY', 'Ghana', 'GH')
       RETURNING id`,
    );
    await expect(
      database.pool.query('UPDATE org_units SET parent_id = $1 WHERE id = $2', [
        otherCountry.rows[0].id,
        region.rows[0].id,
      ]),
    ).rejects.toThrow(/use move_org_unit/i);
  });
});
