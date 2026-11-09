import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { migrateDown, migrateUp } from '../src/database/migrations.js';
import type { TestDatabase } from './support/embedded-postgres.js';
import { createTestDatabase } from './support/embedded-postgres.js';

describe('follow-up scheduler migration rollback', () => {
  let database: TestDatabase;

  beforeAll(async () => {
    database = await createTestDatabase();
  }, 30_000);

  afterAll(async () => {
    await database.close();
  });

  it('rolls back and reapplies completion, scheduler and cadence schema in dependency order', async () => {
    const client = await database.pool.connect();
    try {
      await expect(migrateDown(client)).resolves.toBe('0018_follow_up_completion');
      await expect(migrateDown(client)).resolves.toBe('0017_follow_up_timeline_event');
      await expect(migrateDown(client)).resolves.toBe('0016_follow_up_scheduler');
      const afterSchedulerRollback = await client.query<{
        jobs_table: string | null;
        recurrence_column: string | null;
      }>(
        `SELECT
           to_regclass('public.follow_up_reminder_jobs')::text AS jobs_table,
           (
             SELECT column_name
             FROM information_schema.columns
             WHERE table_schema = 'public'
               AND table_name = 'follow_up_tasks'
               AND column_name = 'recurrence_interval_days'
           ) AS recurrence_column`,
      );
      expect(afterSchedulerRollback.rows[0]).toEqual({ jobs_table: null, recurrence_column: null });

      await expect(migrateDown(client)).resolves.toBe('0015_follow_up_cadence');
      const cadenceAfterRollback = await client.query<{ cadence_table: string | null }>(
        `SELECT to_regclass('public.follow_up_cadence_steps')::text AS cadence_table`,
      );
      expect(cadenceAfterRollback.rows[0]).toEqual({ cadence_table: null });

      await expect(migrateUp(client)).resolves.toEqual([
        '0015_follow_up_cadence',
        '0016_follow_up_scheduler',
        '0017_follow_up_timeline_event',
        '0018_follow_up_completion',
      ]);
      const afterReapply = await client.query<{
        jobs_table: string | null;
        recurrence_column: string | null;
        completed_by_column: string | null;
      }>(
        `SELECT
           to_regclass('public.follow_up_reminder_jobs')::text AS jobs_table,
           (
             SELECT column_name
             FROM information_schema.columns
             WHERE table_schema = 'public'
               AND table_name = 'follow_up_tasks'
               AND column_name = 'recurrence_interval_days'
           ) AS recurrence_column,
           (
             SELECT column_name
             FROM information_schema.columns
             WHERE table_schema = 'public'
               AND table_name = 'follow_up_tasks'
               AND column_name = 'completed_by'
           ) AS completed_by_column`,
      );
      expect(afterReapply.rows[0]).toEqual({
        jobs_table: 'follow_up_reminder_jobs',
        recurrence_column: 'recurrence_interval_days',
        completed_by_column: 'completed_by',
      });
    } finally {
      client.release();
    }
  });
});
