import { ConfigService } from '@nestjs/config';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { AuditService } from '../src/audit/audit.service.js';
import type { AuthenticatedActor } from '../src/authorization/authorization.types.js';
import { ConvertsService } from '../src/converts/converts.service.js';
import { DatabaseService } from '../src/database/database.service.js';
import { FollowUpReminderQueueService } from '../src/follow-up/follow-up-reminder-queue.service.js';
import { FollowUpSchedulerService } from '../src/follow-up/follow-up-scheduler.service.js';
import { FieldEncryptionService } from '../src/privacy/field-encryption.service.js';
import { PrivacySettingsService } from '../src/privacy/privacy-settings.service.js';
import type { TestDatabase } from './support/embedded-postgres.js';
import { createTestDatabase } from './support/embedded-postgres.js';

const auditSecret = 'scheduler-test-audit-secret-which-is-at-least-thirty-two-bytes';
const piiKey = Buffer.alloc(32, 8).toString('base64');

interface Unit {
  id: string;
  path: string;
}

interface ParishActor extends AuthenticatedActor {
  homeUnitId: string;
  homePath: string;
}

describe('FollowUpSchedulerService', () => {
  let testDatabase: TestDatabase;
  let database: DatabaseService;
  let converts: ConvertsService;
  let scheduler: FollowUpSchedulerService;
  let reminderQueue: FollowUpReminderQueueService;
  let parishActor: ParishActor;

  beforeAll(async () => {
    testDatabase = await createTestDatabase();
    const config = new ConfigService({
      DATABASE_URL: testDatabase.connectionString,
      AUDIT_CHAIN_SECRET: auditSecret,
      PII_ENCRYPTION_KEY: piiKey,
      PII_LOOKUP_PEPPER: 'scheduler-test-lookup-pepper-which-is-at-least-thirty-two-bytes',
      FOLLOW_UP_SCHEDULER_ENABLED: false,
    });
    database = new DatabaseService(config);
    const audit = new AuditService();
    converts = new ConvertsService(
      database,
      new FieldEncryptionService(config),
      audit,
      config,
      new PrivacySettingsService(database, audit, config),
    );
    scheduler = new FollowUpSchedulerService(database, config);
    reminderQueue = new FollowUpReminderQueueService(database);

    const units = new Map<string, Unit>();
    async function addUnit(type: string, code: string, parentCode?: string): Promise<void> {
      const inserted = await testDatabase.pool.query<Unit>(
        `INSERT INTO org_units (type, name, code, parent_id)
         VALUES ($1::org_unit_type, $2, $3, $4)
         RETURNING id, path::text`,
        [type, code, code, parentCode ? units.get(parentCode)?.id : null],
      );
      units.set(code, inserted.rows[0]);
    }

    await addUnit('COUNTRY', 'NG');
    await addUnit('REGION', 'NG-REG', 'NG');
    await addUnit('PROVINCE', 'NG-PRO', 'NG-REG');
    await addUnit('ZONE', 'NG-ZON', 'NG-PRO');
    await addUnit('AREA', 'NG-ARE', 'NG-ZON');
    await addUnit('PARISH', 'NG-PAR', 'NG-ARE');

    const user = await testDatabase.pool.query<{ id: string }>(
      `INSERT INTO users (display_name, email_normalized, home_unit_id, status)
       VALUES ('Scheduler Parish Worker', 'scheduler.parish.worker@test.invalid', $1, 'ACTIVE')
       RETURNING id`,
      [units.get('NG-PAR')?.id],
    );
    await testDatabase.pool.query(
      `INSERT INTO user_roles (user_id, role_id, assigned_by)
       SELECT $1, id, $1 FROM roles WHERE key = 'SOUL_WINNER'`,
      [user.rows[0].id],
    );
    const parish = units.get('NG-PAR')!;
    parishActor = {
      id: user.rows[0].id,
      sessionId: '00000000-0000-0000-0000-000000000071',
      roles: ['SOUL_WINNER'],
      homeUnitId: parish.id,
      homePath: parish.path,
      isGlobalAdmin: false,
    };
  }, 30_000);

  afterAll(async () => {
    scheduler.onModuleDestroy();
    await database.onModuleDestroy();
    await testDatabase.close();
  });

  it('materializes a recurring check-in and durable reminder jobs exactly once across retries', async () => {
    const convert = await converts.create(parishActor, {
      fullName: 'Scheduler Journey Convert',
      consent: { granted: true, version: '2026-11', method: 'DIGITAL' },
    });
    const now = new Date('2026-12-01T12:00:00.000Z');

    await testDatabase.pool.query(
      `UPDATE follow_up_tasks
       SET due_at = $2, status = 'COMPLETED', completed_at = $1
       WHERE convert_id = $3 AND task_type = 'WEEKLY_CHECK_IN'`,
      [now, new Date('2026-11-24T12:00:00.000Z'), convert.id],
    );
    await testDatabase.pool.query(
      `UPDATE follow_up_tasks
       SET due_at = $1
       WHERE convert_id = $2 AND task_type = 'CALL_24H'`,
      [new Date('2026-12-01T11:00:00.000Z'), convert.id],
    );
    await testDatabase.pool.query(
      `UPDATE follow_up_tasks
       SET status = 'CANCELLED'
       WHERE convert_id = $1 AND task_type IN ('PRAYER_DAY_3', 'VISIT_DAY_7')`,
      [convert.id],
    );

    const runs = await Promise.all([scheduler.run(now), scheduler.run(now)]);
    expect(runs.reduce((sum, run) => sum + run.materializedRecurringTasks, 0)).toBe(1);
    expect(runs.reduce((sum, run) => sum + run.enqueuedReminderJobs, 0)).toBe(2);

    const recurringTasks = await testDatabase.pool.query<{
      occurrence_number: number;
      recurrence_interval_days: number;
      generated_from_task_id: string | null;
      due_at: Date;
    }>(
      `SELECT occurrence_number, recurrence_interval_days, generated_from_task_id, due_at
       FROM follow_up_tasks
       WHERE convert_id = $1 AND task_type = 'WEEKLY_CHECK_IN'
       ORDER BY occurrence_number`,
      [convert.id],
    );
    expect(recurringTasks.rows).toHaveLength(2);
    expect(recurringTasks.rows[0]).toMatchObject({
      occurrence_number: 1,
      recurrence_interval_days: 7,
      generated_from_task_id: null,
    });
    expect(recurringTasks.rows[1]).toMatchObject({
      occurrence_number: 2,
      recurrence_interval_days: 7,
      due_at: now,
    });
    expect(typeof recurringTasks.rows[1].generated_from_task_id).toBe('string');

    const queued = await testDatabase.pool.query<{
      id: string;
      follow_up_task_id: string;
      idempotency_key: string;
      status: string;
    }>(
      `SELECT id, follow_up_task_id, idempotency_key, status::text
       FROM follow_up_reminder_jobs
       ORDER BY id`,
    );
    expect(queued.rows).toHaveLength(2);
    expect(queued.rows.map((job) => job.status)).toEqual(['PENDING', 'PENDING']);
    expect(queued.rows.map((job) => job.idempotency_key)).toEqual(
      queued.rows.map((job) => `follow-up-task:${job.follow_up_task_id}:due-reminder`),
    );

    const originalWorker = '00000000-0000-0000-0000-000000000081';
    const claimed = await reminderQueue.claim(originalWorker, 10, now);
    expect(claimed).toHaveLength(2);
    expect(claimed.map((job) => job.attempts)).toEqual([1, 1]);

    const retriedJob = claimed[0];
    const retainedClaim = claimed[1];
    const retryAt = new Date('2026-12-01T12:05:00.000Z');
    await expect(
      reminderQueue.retry(
        retriedJob.id,
        originalWorker,
        'TRANSIENT_PROVIDER_FAILURE',
        retryAt,
        now,
      ),
    ).resolves.toBe('PENDING');
    await reminderQueue.markDelivered(retainedClaim.id, originalWorker, now);

    const repeatedRun = await scheduler.run(retryAt);
    expect(repeatedRun).toMatchObject({
      materializedRecurringTasks: 0,
      enqueuedReminderJobs: 0,
    });

    const retryWorker = '00000000-0000-0000-0000-000000000082';
    const retryClaim = await reminderQueue.claim(retryWorker, 10, retryAt);
    expect(retryClaim).toEqual([expect.objectContaining({ id: retriedJob.id, attempts: 2 })]);
    await reminderQueue.markDelivered(retriedJob.id, retryWorker, retryAt);

    const finalJobs = await testDatabase.pool.query<{
      status: string;
      attempts: number;
    }>(`SELECT status::text, attempts FROM follow_up_reminder_jobs ORDER BY attempts`);
    expect(finalJobs.rows).toEqual([
      { status: 'DELIVERED', attempts: 1 },
      { status: 'DELIVERED', attempts: 2 },
    ]);
  });
});
