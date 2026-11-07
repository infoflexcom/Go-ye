import { Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import type { PoolClient } from 'pg';
import { DatabaseService } from '../database/database.service.js';

export type FollowUpReminderJobStatus =
  'PENDING' | 'PROCESSING' | 'DELIVERED' | 'CANCELLED' | 'DEAD_LETTER';

interface ClaimedReminderJobRow {
  id: string;
  follow_up_task_id: string;
  idempotency_key: string;
  attempts: number;
}

export interface ClaimedFollowUpReminderJob {
  id: string;
  followUpTaskId: string;
  idempotencyKey: string;
  attempts: number;
}

@Injectable()
export class FollowUpReminderQueueService {
  constructor(private readonly database: DatabaseService) {}

  async claim(
    workerId: string = randomUUID(),
    limit: number = 25,
    now: Date = new Date(),
  ): Promise<ClaimedFollowUpReminderJob[]> {
    return this.withSystemActor(async (client) => {
      const claimed = await client.query<ClaimedReminderJobRow>(
        `SELECT id, follow_up_task_id, idempotency_key, attempts
         FROM goye_claim_follow_up_reminder_jobs($1::uuid, $2, $3)`,
        [workerId, limit, now],
      );
      return claimed.rows.map((row) => ({
        id: row.id,
        followUpTaskId: row.follow_up_task_id,
        idempotencyKey: row.idempotency_key,
        attempts: row.attempts,
      }));
    });
  }

  async markDelivered(
    jobId: string,
    workerId: string,
    deliveredAt: Date = new Date(),
  ): Promise<void> {
    await this.withSystemActor(async (client) => {
      await client.query(
        `SELECT goye_mark_follow_up_reminder_job_delivered($1::uuid, $2::uuid, $3)`,
        [jobId, workerId, deliveredAt],
      );
    });
  }

  async retry(
    jobId: string,
    workerId: string,
    errorCode: string,
    availableAt: Date,
    updatedAt: Date = new Date(),
  ): Promise<FollowUpReminderJobStatus> {
    return this.withSystemActor(async (client) => {
      const result = await client.query<{ status: FollowUpReminderJobStatus }>(
        `SELECT goye_retry_follow_up_reminder_job($1::uuid, $2::uuid, $3, $4, $5)::text AS status`,
        [jobId, workerId, errorCode, availableAt, updatedAt],
      );
      return result.rows[0].status;
    });
  }

  private async withSystemActor<T>(callback: (client: PoolClient) => Promise<T>): Promise<T> {
    return this.database.withActor({ isSystem: true }, callback);
  }
}
