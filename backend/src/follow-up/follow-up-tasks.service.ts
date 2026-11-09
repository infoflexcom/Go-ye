import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { PoolClient } from 'pg';
import { AuditService } from '../audit/audit.service.js';
import type { AuthenticatedActor } from '../authorization/authorization.types.js';
import { DatabaseService } from '../database/database.service.js';
import { FieldEncryptionService } from '../privacy/field-encryption.service.js';
import { maskPhoneNumber, PrivacySettingsService } from '../privacy/privacy-settings.service.js';
import type {
  CompleteFollowUpTaskDto,
  FollowUpTaskOutcome,
} from './dto/complete-follow-up-task.dto.js';
import type { RegisterPushTokenDto } from './dto/register-push-token.dto.js';
import type { FollowUpTaskType } from './follow-up-cadence.service.js';

const followUpWorkerRoles = new Set([
  'COUNTRY_ADMIN',
  'REGION_LEADER',
  'PROVINCE_LEADER',
  'ZONE_LEADER',
  'AREA_LEADER',
  'PARISH_PASTOR',
  'SOUL_WINNER',
  'FOLLOW_UP_WORKER',
]);

const pushRecipientRoles = ['PARISH_PASTOR', 'SOUL_WINNER', 'FOLLOW_UP_WORKER'];

interface FollowUpTaskRow {
  id: string;
  convert_id: string;
  parish_id: string;
  task_type: FollowUpTaskType;
  occurrence_number: number;
  due_at: Date;
  status: 'PENDING' | 'COMPLETED' | 'CANCELLED';
  outcome: FollowUpTaskOutcome | null;
  outcome_note_encrypted: Buffer | null;
  completed_at: Date | null;
  completed_by: string | null;
  full_name_encrypted: Buffer;
  phone_encrypted: Buffer | null;
}

interface PushDeviceRow {
  id: string;
  push_token_encrypted: Buffer;
}

export interface FollowUpTask {
  id: string;
  convertId: string;
  parishId: string;
  taskType: FollowUpTaskType;
  occurrenceNumber: number;
  dueAt: Date;
  status: 'PENDING' | 'COMPLETED' | 'CANCELLED';
  convertName: string;
  phone?: string;
  outcome?: FollowUpTaskOutcome;
  note?: string;
  completedAt?: Date;
  completedBy?: string;
}

export interface FollowUpPushRecipientLookup {
  taskIsActive: boolean;
  tokens: { deviceId: string; token: string }[];
}

@Injectable()
export class FollowUpTasksService {
  constructor(
    private readonly database: DatabaseService,
    private readonly encryption: FieldEncryptionService,
    private readonly privacySettings: PrivacySettingsService,
    private readonly audit: AuditService,
    private readonly config: ConfigService,
  ) {}

  async listToday(actor: AuthenticatedActor, now: Date = new Date()): Promise<FollowUpTask[]> {
    this.assertFollowUpWorker(actor);
    return this.withActor(actor, async (client) => {
      const todayStart = await this.todayStart(client, now);
      const tasks = await client.query<FollowUpTaskRow>(
        `SELECT task.id, task.convert_id, task.parish_id, task.task_type::text,
                task.occurrence_number, task.due_at, task.status::text,
                task.outcome::text, task.outcome_note_encrypted, task.completed_at,
                task.completed_by, convert.full_name_encrypted, convert.phone_encrypted
         FROM follow_up_tasks task
         JOIN converts convert ON convert.id = task.convert_id
         WHERE task.status = 'PENDING'
           AND task.due_at >= $1
           AND task.due_at < $1 + interval '1 day'
           AND convert.privacy_status = 'ACTIVE'
           AND convert.merged_into_id IS NULL
         ORDER BY task.due_at ASC, task.id ASC`,
        [todayStart],
      );
      await this.auditAboveParishRead(client, actor, 'FOLLOW_UP_TODAY_READ_ABOVE_PARISH', {
        metadata: { resultCount: tasks.rows.length, timeZone: this.timeZone() },
      });
      const maskPhone = await this.privacySettings.maskPhoneNumbersAboveParish(client, actor);
      return tasks.rows.map((task) => this.toTask(task, maskPhone));
    });
  }

  async complete(
    actor: AuthenticatedActor,
    taskId: string,
    dto: CompleteFollowUpTaskDto,
  ): Promise<FollowUpTask> {
    this.assertFollowUpWorker(actor);
    const note = dto.note === undefined ? undefined : this.requiredText(dto.note, 'note');
    const outcome = dto.outcome ?? 'COMPLETED';
    return this.withActor(actor, async (client) => {
      await client.query(
        `SELECT goye_complete_follow_up_task($1::uuid, $2::uuid, $3::follow_up_task_outcome, $4)`,
        [taskId, actor.id, outcome, note ? this.encryption.encrypt(note) : null],
      );
      const result = await client.query<FollowUpTaskRow>(
        `SELECT task.id, task.convert_id, task.parish_id, task.task_type::text,
                task.occurrence_number, task.due_at, task.status::text,
                task.outcome::text, task.outcome_note_encrypted, task.completed_at,
                task.completed_by, convert.full_name_encrypted, convert.phone_encrypted
         FROM follow_up_tasks task
         JOIN converts convert ON convert.id = task.convert_id
         WHERE task.id = $1`,
        [taskId],
      );
      const task = result.rows[0];
      if (!task) {
        throw new NotFoundException('Follow-up task not found.');
      }
      await this.audit.append(client, {
        actorUserId: actor.id,
        action: 'FOLLOW_UP_TASK_COMPLETED',
        resourceType: 'FOLLOW_UP_TASK',
        resourceId: task.id,
        scopeUnitId: task.parish_id,
        metadata: {
          taskType: task.task_type,
          occurrenceNumber: task.occurrence_number,
          outcome,
          noteRecorded: note !== undefined,
        },
      });
      return this.toTask(
        task,
        await this.privacySettings.maskPhoneNumbersAboveParish(client, actor),
      );
    });
  }

  async registerPushToken(
    actor: AuthenticatedActor,
    dto: RegisterPushTokenDto,
  ): Promise<{ registered: true }> {
    this.assertFollowUpWorker(actor);
    const token = this.requiredText(dto.token, 'token');
    return this.withActor(actor, async (client) => {
      const device = await client.query<{ id: string; parish_id: string | null }>(
        `UPDATE devices device
         SET push_token_encrypted = $1,
             last_seen_at = now(),
             updated_at = now()
         FROM sessions session, users user_account
         WHERE user_account.id = device.user_id
           AND session.id = $2
           AND session.user_id = $3
           AND session.status = 'ACTIVE'
           AND session.expires_at > now()
           AND session.device_id = device.id
           AND device.user_id = $3
           AND device.platform = 'ANDROID'
           AND device.revoked_at IS NULL
         RETURNING device.id, user_account.home_unit_id AS parish_id`,
        [this.encryption.encrypt(token), actor.sessionId, actor.id],
      );
      const registered = device.rows[0];
      if (!registered) {
        throw new BadRequestException(
          'Push notifications require an active Android device session. Sign in again on this device.',
        );
      }
      await this.audit.append(client, {
        actorUserId: actor.id,
        action: 'FOLLOW_UP_PUSH_TOKEN_REGISTERED',
        resourceType: 'DEVICE',
        resourceId: registered.id,
        scopeUnitId: registered.parish_id ?? undefined,
        metadata: { platform: 'ANDROID' },
      });
      return { registered: true };
    });
  }

  async eligiblePushRecipients(taskId: string): Promise<FollowUpPushRecipientLookup> {
    return this.database.withActor({ isSystem: true }, async (client) => {
      const task = await client.query<{ parish_id: string }>(
        `SELECT task.parish_id
         FROM follow_up_tasks task
         JOIN converts convert ON convert.id = task.convert_id
         WHERE task.id = $1
           AND task.status = 'PENDING'
           AND convert.privacy_status = 'ACTIVE'
           AND convert.merged_into_id IS NULL`,
        [taskId],
      );
      const taskRow = task.rows[0];
      if (!taskRow) {
        return { taskIsActive: false, tokens: [] };
      }
      const recipients = await client.query<PushDeviceRow>(
        `SELECT DISTINCT device.id, device.push_token_encrypted
         FROM devices device
         JOIN users user_account ON user_account.id = device.user_id
         JOIN user_roles role_assignment ON role_assignment.user_id = user_account.id
         JOIN roles role_lookup ON role_lookup.id = role_assignment.role_id
         WHERE device.push_token_encrypted IS NOT NULL
           AND device.platform = 'ANDROID'
           AND device.revoked_at IS NULL
           AND user_account.status = 'ACTIVE'
           AND user_account.home_unit_id = $1
           AND role_lookup.key = ANY($2::text[])
           AND EXISTS (
             SELECT 1
             FROM sessions session
             WHERE session.device_id = device.id
               AND session.user_id = device.user_id
               AND session.status = 'ACTIVE'
               AND session.expires_at > now()
           )`,
        [taskRow.parish_id, pushRecipientRoles],
      );
      return {
        taskIsActive: true,
        tokens: recipients.rows.map((recipient) => ({
          deviceId: recipient.id,
          token: this.encryption.decrypt(recipient.push_token_encrypted),
        })),
      };
    });
  }

  async clearPushToken(deviceId: string): Promise<void> {
    await this.database.withActor({ isSystem: true }, async (client) => {
      await client.query(
        `UPDATE devices
         SET push_token_encrypted = NULL, updated_at = now()
         WHERE id = $1`,
        [deviceId],
      );
    });
  }

  private async todayStart(client: PoolClient, now: Date): Promise<Date> {
    const result = await client.query<{ today_start: Date }>(
      `SELECT (date_trunc('day', $1::timestamptz AT TIME ZONE $2) AT TIME ZONE $2) AS today_start`,
      [now, this.timeZone()],
    );
    return result.rows[0].today_start;
  }

  private toTask(row: FollowUpTaskRow, maskPhone: boolean): FollowUpTask {
    const phone = row.phone_encrypted ? this.encryption.decrypt(row.phone_encrypted) : undefined;
    return {
      id: row.id,
      convertId: row.convert_id,
      parishId: row.parish_id,
      taskType: row.task_type,
      occurrenceNumber: row.occurrence_number,
      dueAt: row.due_at,
      status: row.status,
      convertName: this.encryption.decrypt(row.full_name_encrypted),
      ...(phone ? { phone: maskPhone ? maskPhoneNumber(phone) : phone } : {}),
      ...(row.outcome ? { outcome: row.outcome } : {}),
      ...(row.outcome_note_encrypted
        ? { note: this.encryption.decrypt(row.outcome_note_encrypted) }
        : {}),
      ...(row.completed_at ? { completedAt: row.completed_at } : {}),
      ...(row.completed_by ? { completedBy: row.completed_by } : {}),
    };
  }

  private async withActor<T>(
    actor: AuthenticatedActor,
    callback: (client: PoolClient) => Promise<T>,
  ): Promise<T> {
    return this.database.withActor(
      {
        userId: actor.id,
        homePath: actor.homePath,
        isGlobalAdmin: actor.isGlobalAdmin,
        auditSecret: this.auditSecret(),
      },
      callback,
    );
  }

  private assertFollowUpWorker(actor: AuthenticatedActor): void {
    if (actor.isGlobalAdmin) {
      return;
    }
    if (
      !actor.homeUnitId ||
      !actor.homePath ||
      !actor.roles.some((role) => followUpWorkerRoles.has(role))
    ) {
      throw new ForbiddenException('The active role and home unit do not permit follow-up work.');
    }
  }

  private async auditAboveParishRead(
    client: PoolClient,
    actor: AuthenticatedActor,
    action: string,
    details: { metadata: Record<string, unknown> },
  ): Promise<void> {
    if (!actor.isGlobalAdmin) {
      if (!actor.homeUnitId) {
        return;
      }
      const home = await client.query<{ type: string }>(
        `SELECT type::text FROM org_units WHERE id = $1`,
        [actor.homeUnitId],
      );
      if (home.rows[0]?.type === 'PARISH') {
        return;
      }
    }
    await this.audit.append(client, {
      actorUserId: actor.id,
      action,
      resourceType: 'FOLLOW_UP_TASK',
      scopeUnitId: actor.homeUnitId,
      metadata: details.metadata,
    });
  }

  private requiredText(value: string, field: string): string {
    const normalized = value.trim();
    if (!normalized) {
      throw new BadRequestException(`${field} must not be blank.`);
    }
    return normalized;
  }

  private auditSecret(): string {
    const secret = this.config.get<string>('AUDIT_CHAIN_SECRET');
    if (!secret || secret.startsWith('replace-with-') || secret.length < 32) {
      throw new Error('AUDIT_CHAIN_SECRET must be configured for follow-up operations.');
    }
    return secret;
  }

  private timeZone(): string {
    return this.config.get<string>('FOLLOW_UP_TIME_ZONE', 'Africa/Lagos');
  }
}
