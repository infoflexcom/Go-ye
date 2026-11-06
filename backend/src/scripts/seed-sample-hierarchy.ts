import { Pool } from 'pg';
import { migrateUp } from '../database/migrations.js';
import { applyHierarchyImport, type HierarchyImportRow } from '../hierarchy/hierarchy-import.js';
import { beginSystemTransaction, requiredEnvironment } from './database-script.util.js';

const sampleHierarchy: HierarchyImportRow[] = [
  { type: 'COUNTRY', name: 'Nigeria', code: 'NG', isActive: true },
  { type: 'REGION', name: 'Lagos Region', code: 'NG-LAG-REG', parentCode: 'NG', isActive: true },
  {
    type: 'PROVINCE',
    name: 'Lagos Province One',
    code: 'NG-LAG-PRO-1',
    parentCode: 'NG-LAG-REG',
    isActive: true,
  },
  {
    type: 'ZONE',
    name: 'Lagos Zone One',
    code: 'NG-LAG-ZON-1',
    parentCode: 'NG-LAG-PRO-1',
    isActive: true,
  },
  {
    type: 'AREA',
    name: 'Lagos Area One',
    code: 'NG-LAG-ARE-1',
    parentCode: 'NG-LAG-ZON-1',
    isActive: true,
  },
  {
    type: 'PARISH',
    name: 'Sample Parish Alpha',
    code: 'NG-LAG-PAR-A',
    parentCode: 'NG-LAG-ARE-1',
    isActive: true,
  },
  {
    type: 'PARISH',
    name: 'Sample Parish Beta',
    code: 'NG-LAG-PAR-B',
    parentCode: 'NG-LAG-ARE-1',
    isActive: true,
  },
  { type: 'COUNTRY', name: 'Ghana', code: 'GH', isActive: true },
  { type: 'REGION', name: 'Accra Region', code: 'GH-ACC-REG', parentCode: 'GH', isActive: true },
  {
    type: 'PROVINCE',
    name: 'Accra Province One',
    code: 'GH-ACC-PRO-1',
    parentCode: 'GH-ACC-REG',
    isActive: true,
  },
  {
    type: 'ZONE',
    name: 'Accra Zone One',
    code: 'GH-ACC-ZON-1',
    parentCode: 'GH-ACC-PRO-1',
    isActive: true,
  },
  {
    type: 'AREA',
    name: 'Accra Area One',
    code: 'GH-ACC-ARE-1',
    parentCode: 'GH-ACC-ZON-1',
    isActive: true,
  },
  {
    type: 'PARISH',
    name: 'Sample Parish Accra',
    code: 'GH-ACC-PAR-A',
    parentCode: 'GH-ACC-ARE-1',
    isActive: true,
  },
];

async function main(): Promise<void> {
  if (process.env.ALLOW_SAMPLE_SEED !== 'true') {
    throw new Error('Set ALLOW_SAMPLE_SEED=true to load non-production sample data.');
  }
  const pool = new Pool({ connectionString: requiredEnvironment('DATABASE_URL') });
  const auditSecret = requiredEnvironment('AUDIT_CHAIN_SECRET');
  const client = await pool.connect();
  try {
    await migrateUp(client);
    await beginSystemTransaction(client, auditSecret);
    const result = await applyHierarchyImport(client, sampleHierarchy);
    const admin = await client.query<{ id: string }>(
      `INSERT INTO users (display_name, email_normalized, status)
       VALUES ('Sample Global Admin', 'sample.global.admin@example.test', 'ACTIVE')
       ON CONFLICT (email_normalized) DO UPDATE SET display_name = EXCLUDED.display_name
       RETURNING id`,
    );
    await client.query(
      `INSERT INTO user_roles (user_id, role_id, assigned_by)
       SELECT $1, id, $1 FROM roles WHERE key = 'GLOBAL_ADMIN'
       ON CONFLICT (user_id, role_id) DO NOTHING`,
      [admin.rows[0].id],
    );
    await client.query(
      `SELECT goye_append_audit_event($1, 'SYSTEM_SAMPLE_HIERARCHY_SEEDED', 'HIERARCHY_IMPORT', NULL, NULL, $2::jsonb)`,
      [admin.rows[0].id, JSON.stringify(result)],
    );
    await client.query('COMMIT');
    console.log(JSON.stringify({ mode: 'sample-seed', ...result }));
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
    await pool.end();
  }
}

void main();
