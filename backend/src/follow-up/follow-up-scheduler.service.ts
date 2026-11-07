import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { PoolClient } from 'pg';
import { DatabaseService } from '../database/database.service.js';

export interface FollowUpSchedulingRun {
  materializedRecurringTasks: number;
  enqueuedReminderJobs: number;
  cancelledReminderJobs: number;
  deadLetteredReminderJobs: number;
}

@Injectable()
export class FollowUpSchedulerService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(FollowUpSchedulerService.name);
  private interval?: NodeJS.Timeout;
  private tickInProgress = false;

  constructor(
    private readonly database: DatabaseService,
    private readonly config: ConfigService,
  ) {}

  async onModuleInit(): Promise<void> {
    if (!this.database.isConfigured() || !this.isEnabled()) {
      return;
    }

    await this.runSafely();
    this.interval = setInterval(() => {
      void this.runSafely();
    }, this.intervalMilliseconds());
    this.interval.unref();
  }

  onModuleDestroy(): void {
    if (this.interval) {
      clearInterval(this.interval);
    }
  }

  async run(now: Date = new Date()): Promise<FollowUpSchedulingRun> {
    return this.database.withActor({ isSystem: true }, async (client) => {
      const materializedRecurringTasks = await this.materializeRecurringTasks(client);
      const cancelledReminderJobs = await this.cancelInvalidReminderJobs(client, now);
      const deadLetteredReminderJobs = await this.deadLetterExpiredClaims(client, now);
      const enqueuedReminderJobs = await this.enqueueDueReminders(client, now);
      return {
        materializedRecurringTasks,
        enqueuedReminderJobs,
        cancelledReminderJobs,
        deadLetteredReminderJobs,
      };
    });
  }

  private async runSafely(): Promise<void> {
    if (this.tickInProgress) {
      return;
    }
    this.tickInProgress = true;
    try {
      const result = await this.run();
      if (
        result.materializedRecurringTasks > 0 ||
        result.enqueuedReminderJobs > 0 ||
        result.cancelledReminderJobs > 0 ||
        result.deadLetteredReminderJobs > 0
      ) {
        this.logger.log(
          `Follow-up scheduler materialized ${result.materializedRecurringTasks} task(s), enqueued ${result.enqueuedReminderJobs} reminder job(s), cancelled ${result.cancelledReminderJobs}, and dead-lettered ${result.deadLetteredReminderJobs}.`,
        );
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unknown scheduler failure';
      this.logger.error(`Follow-up scheduler run failed: ${message}`);
    } finally {
      this.tickInProgress = false;
    }
  }

  private async materializeRecurringTasks(client: PoolClient): Promise<number> {
    const inserted = await client.query<{ id: string }>(
      `WITH eligible_predecessors AS (
         SELECT task.id, task.convert_id, task.parish_id, task.task_type,
                task.cadence_step_id, task.occurrence_number,
                task.recurrence_interval_days, task.due_at
         FROM follow_up_tasks task
         JOIN converts convert ON convert.id = task.convert_id
         LEFT JOIN follow_up_tasks successor ON successor.generated_from_task_id = task.id
         WHERE task.status = 'COMPLETED'
           AND task.recurrence_interval_days IS NOT NULL
           AND convert.privacy_status = 'ACTIVE'
           AND convert.merged_into_id IS NULL
           AND successor.id IS NULL
       )
       INSERT INTO follow_up_tasks (
         convert_id, parish_id, task_type, cadence_step_id, occurrence_number,
         recurrence_interval_days, generated_from_task_id, due_at
       )
       SELECT
         predecessor.convert_id,
         predecessor.parish_id,
         predecessor.task_type,
         predecessor.cadence_step_id,
         predecessor.occurrence_number + 1,
         predecessor.recurrence_interval_days,
         predecessor.id,
         predecessor.due_at + make_interval(days => predecessor.recurrence_interval_days)
       FROM eligible_predecessors predecessor
       ON CONFLICT ON CONSTRAINT follow_up_tasks_convert_cadence_occurrence_unique DO NOTHING
       RETURNING id`,
    );
    return inserted.rowCount ?? 0;
  }

  private async cancelInvalidReminderJobs(client: PoolClient, now: Date): Promise<number> {
    const cancelled = await client.query<{ id: string }>(
      `UPDATE follow_up_reminder_jobs job
       SET status = 'CANCELLED',
           locked_by = NULL,
           locked_at = NULL,
           updated_at = $1
       FROM follow_up_tasks task
       JOIN converts convert ON convert.id = task.convert_id
       WHERE job.follow_up_task_id = task.id
         AND job.status = 'PENDING'
         AND (
           task.status <> 'PENDING'
           OR convert.privacy_status <> 'ACTIVE'
           OR convert.merged_into_id IS NOT NULL
         )
       RETURNING job.id`,
      [now],
    );
    return cancelled.rowCount ?? 0;
  }

  private async deadLetterExpiredClaims(client: PoolClient, now: Date): Promise<number> {
    const deadLettered = await client.query<{ id: string }>(
      `UPDATE follow_up_reminder_jobs
       SET status = 'DEAD_LETTER',
           locked_by = NULL,
           locked_at = NULL,
           last_error_code = 'DELIVERY_RETRY_LIMIT',
           updated_at = $1
       WHERE status = 'PROCESSING'
         AND attempts >= 8
         AND locked_at < ($1::timestamptz - interval '5 minutes')
       RETURNING id`,
      [now],
    );
    return deadLettered.rowCount ?? 0;
  }

  private async enqueueDueReminders(client: PoolClient, now: Date): Promise<number> {
    const enqueued = await client.query<{ id: string }>(
      `INSERT INTO follow_up_reminder_jobs (
         follow_up_task_id, idempotency_key, available_at
       )
       SELECT
         task.id,
         'follow-up-task:' || task.id::text || ':due-reminder',
         task.due_at
       FROM follow_up_tasks task
       JOIN converts convert ON convert.id = task.convert_id
       WHERE task.status = 'PENDING'
         AND task.due_at <= $1
         AND convert.privacy_status = 'ACTIVE'
         AND convert.merged_into_id IS NULL
       ON CONFLICT ON CONSTRAINT follow_up_reminder_jobs_task_type_unique DO NOTHING
       RETURNING id`,
      [now],
    );
    return enqueued.rowCount ?? 0;
  }

  private isEnabled(): boolean {
    return this.config.get<boolean>('FOLLOW_UP_SCHEDULER_ENABLED', true);
  }

  private intervalMilliseconds(): number {
    return this.config.get<number>('FOLLOW_UP_SCHEDULER_INTERVAL_SECONDS', 60) * 1000;
  }
}
