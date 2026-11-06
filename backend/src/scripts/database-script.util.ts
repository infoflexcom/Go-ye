import type { PoolClient } from 'pg';

export async function beginSystemTransaction(
  client: PoolClient,
  auditSecret: string,
): Promise<void> {
  await client.query('BEGIN');
  await client.query('SET LOCAL ROLE goye_runtime');
  await client.query(
    `SELECT
      set_config('goye.user_id', '', true),
      set_config('goye.home_path', '', true),
      set_config('goye.is_global_admin', 'false', true),
      set_config('goye.is_system', 'true', true),
      set_config('goye.audit_secret', $1, true)`,
    [auditSecret],
  );
}

export function requiredEnvironment(name: string): string {
  const value = process.env[name];
  if (!value || value.startsWith('replace-with-')) {
    throw new Error(`${name} must be set to a real secret or connection value.`);
  }
  return value;
}
