import { Pool } from 'pg';
import { applyHierarchyImport, readHierarchyFile } from '../hierarchy/hierarchy-import.js';
import { beginSystemTransaction, requiredEnvironment } from './database-script.util.js';

function argument(name: string): string | undefined {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

async function main(): Promise<void> {
  const filename = argument('--file');
  const dryRun = process.argv.includes('--dry-run');
  if (!filename) {
    throw new Error('Usage: npm run hierarchy:import -- --file hierarchy.csv|xlsx [--dry-run]');
  }
  const rows = await readHierarchyFile(filename);
  const pool = new Pool({ connectionString: requiredEnvironment('DATABASE_URL') });
  const client = await pool.connect();
  try {
    await beginSystemTransaction(client, requiredEnvironment('AUDIT_CHAIN_SECRET'));
    const result = await applyHierarchyImport(client, rows);
    if (dryRun) {
      await client.query('ROLLBACK');
      console.log(JSON.stringify({ mode: 'dry-run', rows: rows.length, ...result }));
      return;
    }
    await client.query(
      `SELECT goye_append_audit_event(NULL, 'HIERARCHY_IMPORTED', 'HIERARCHY_IMPORT', NULL, NULL, $1::jsonb)`,
      [JSON.stringify({ sourceRows: rows.length, ...result })],
    );
    await client.query('COMMIT');
    console.log(JSON.stringify({ mode: 'applied', rows: rows.length, ...result }));
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
    await pool.end();
  }
}

void main();
