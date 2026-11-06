import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import type { Pool, PoolClient } from 'pg';

export type MigrationDirection = 'up' | 'down';

type SqlExecutor = Pick<Pool | PoolClient, 'query'>;

const migrationsDirectory = join(process.cwd(), 'migrations');

async function migrationFiles(direction: MigrationDirection): Promise<string[]> {
  const suffix = `.${direction}.sql`;
  return (await readdir(migrationsDirectory))
    .filter((file) => /^\d{4}_[a-z0-9_]+\.(up|down)\.sql$/.test(file) && file.endsWith(suffix))
    .sort();
}

export async function ensureMigrationTable(executor: SqlExecutor): Promise<void> {
  await executor.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version text PRIMARY KEY,
      applied_at timestamptz NOT NULL DEFAULT now()
    )
  `);
}

export async function migrateUp(executor: SqlExecutor): Promise<string[]> {
  await ensureMigrationTable(executor);
  const applied = await executor.query<{ version: string }>(
    'SELECT version FROM schema_migrations',
  );
  const appliedVersions = new Set(applied.rows.map((row) => row.version));
  const executed: string[] = [];

  for (const file of await migrationFiles('up')) {
    const version = file.replace(/\.up\.sql$/, '');
    if (appliedVersions.has(version)) {
      continue;
    }
    const sql = await readFile(join(migrationsDirectory, file), 'utf8');
    await executor.query('BEGIN');
    try {
      await executor.query(sql);
      await executor.query('INSERT INTO schema_migrations (version) VALUES ($1)', [version]);
      await executor.query('COMMIT');
      executed.push(version);
    } catch (error) {
      await executor.query('ROLLBACK');
      throw error;
    }
  }
  return executed;
}

export async function migrateDown(executor: SqlExecutor): Promise<string | undefined> {
  await ensureMigrationTable(executor);
  const result = await executor.query<{ version: string }>(
    'SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1',
  );
  const version = result.rows[0]?.version;
  if (!version) {
    return undefined;
  }

  const filename = `${version}.down.sql`;
  const sql = await readFile(join(migrationsDirectory, filename), 'utf8');
  await executor.query('BEGIN');
  try {
    await executor.query(sql);
    await executor.query('DELETE FROM schema_migrations WHERE version = $1', [version]);
    await executor.query('COMMIT');
    return version;
  } catch (error) {
    await executor.query('ROLLBACK');
    throw error;
  }
}
