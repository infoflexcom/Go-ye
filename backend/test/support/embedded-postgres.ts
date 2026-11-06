import EmbeddedPostgres from 'embedded-postgres';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createServer } from 'node:net';
import { Pool } from 'pg';
import { migrateUp } from '../../src/database/migrations.js';

export interface TestDatabase {
  pool: Pool;
  connectionString: string;
  close(): Promise<void>;
}

async function unusedPort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      if (!address || typeof address === 'string') {
        reject(new Error('Unable to allocate an ephemeral test port'));
        return;
      }
      server.close((error) => (error ? reject(error) : resolve(address.port)));
    });
  });
}

export async function createTestDatabase(): Promise<TestDatabase> {
  const directory = await mkdtemp(join(tmpdir(), 'goye-postgres-'));
  const port = await unusedPort();
  const password = 'test-local-only-password';
  const postgres = new EmbeddedPostgres({
    databaseDir: directory,
    port,
    user: 'postgres',
    password,
    persistent: false,
    autoRehydrateSymlinks: true,
    onLog: () => undefined,
    onError: () => undefined,
  });

  await postgres.initialise();
  await postgres.start();
  const connectionString = `postgresql://postgres:${password}@127.0.0.1:${port}/postgres`;
  const pool = new Pool({ connectionString, max: 1 });
  const client = await pool.connect();
  try {
    await migrateUp(client);
  } finally {
    client.release();
  }

  return {
    pool,
    connectionString,
    async close(): Promise<void> {
      await pool.end();
      await postgres.stop();
      await rm(directory, { recursive: true, force: true });
    },
  };
}
