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

  it('rolls back and reapplies escalation, completion, scheduler and cadence schema in dependency order', async () => {
    const client = await database.pool.connect();
    try {
      const escalationIndexBeforeRollback = await client.query<{ index_name: string | null }>(
        `SELECT to_regclass('public.follow_up_tasks_pending_due_escalation_idx')::text AS index_name`,
      );
      expect(escalationIndexBeforeRollback.rows[0].index_name).toBe(
        'follow_up_tasks_pending_due_escalation_idx',
      );
      await expect(migrateDown(client)).resolves.toBe('0019_follow_up_escalations');
      const escalationIndexAfterRollback = await client.query<{ index_name: string | null }>(
        `SELECT to_regclass('public.follow_up_tasks_pending_due_escalation_idx')::text AS index_name`,
      );
      expect(escalationIndexAfterRollback.rows[0].index_name).toBeNull();
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
        '0019_follow_up_escalations',
      ]);
      const afterReapply = await client.query<{
        jobs_table: string | null;
        recurrence_column: string | null;
        completed_by_column: string | null;
        escalation_index: string | null;
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
           ) AS completed_by_column,
           to_regclass('public.follow_up_tasks_pending_due_escalation_idx')::text AS escalation_index`,
      );
      expect(afterReapply.rows[0]).toEqual({
        jobs_table: 'follow_up_reminder_jobs',
        recurrence_column: 'recurrence_interval_days',
        completed_by_column: 'completed_by',
        escalation_index: 'follow_up_tasks_pending_due_escalation_idx',
      });
    } finally {
      client.release();
    }
  });
});
