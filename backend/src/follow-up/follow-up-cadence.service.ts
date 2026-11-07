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

export type FollowUpTaskType = 'CALL_24H' | 'PRAYER_DAY_3' | 'VISIT_DAY_7' | 'WEEKLY_CHECK_IN';

interface CadenceStepRow {
  id: string;
  code: string;
  task_type: FollowUpTaskType;
  label: string;
  due_offset_hours: number;
  recurrence_days: number | null;
  is_active: boolean;
  sort_order: number;
}

export interface FollowUpCadenceStep {
  id: string;
  code: string;
  taskType: FollowUpTaskType;
  label: string;
  dueOffsetHours: number;
  recurrenceDays?: number;
  isActive: boolean;
  sortOrder: number;
}

export interface UpdateFollowUpCadenceStep {
  dueOffsetHours?: number;
  recurrenceDays?: number;
  isActive?: boolean;
}

@Injectable()
export class FollowUpCadenceService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly config: ConfigService,
  ) {}

  async list(actor: AuthenticatedActor): Promise<FollowUpCadenceStep[]> {
    this.assertGlobalAdmin(actor);
    return this.withActor(actor, async (client) => {
      const result = await client.query<CadenceStepRow>(
        `SELECT id, code, task_type::text, label, due_offset_hours, recurrence_days, is_active, sort_order
         FROM follow_up_cadence_steps
         ORDER BY sort_order ASC`,
      );
      return result.rows.map((row) => this.toStep(row));
    });
  }

  async update(
    actor: AuthenticatedActor,
    code: string,
    update: UpdateFollowUpCadenceStep,
  ): Promise<FollowUpCadenceStep> {
    this.assertGlobalAdmin(actor);
    const normalizedCode = code.trim().toUpperCase();
    if (!/^[A-Z][A-Z0-9_]{2,63}$/.test(normalizedCode)) {
      throw new BadRequestException('Cadence step code is invalid.');
    }
    if (Object.values(update).every((value) => value === undefined)) {
      throw new BadRequestException('At least one cadence setting must be supplied.');
    }

    return this.withActor(actor, async (client) => {
      const updated = await client.query<CadenceStepRow>(
        `UPDATE follow_up_cadence_steps
         SET due_offset_hours = COALESCE($2, due_offset_hours),
             recurrence_days = CASE
               WHEN task_type = 'WEEKLY_CHECK_IN' THEN COALESCE($3, recurrence_days)
               ELSE recurrence_days
             END,
             is_active = COALESCE($4, is_active)
         WHERE code = $1
         RETURNING id, code, task_type::text, label, due_offset_hours, recurrence_days, is_active, sort_order`,
        [
          normalizedCode,
          update.dueOffsetHours ?? null,
          update.recurrenceDays ?? null,
          update.isActive ?? null,
        ],
      );
      const row = updated.rows[0];
      if (!row) {
        throw new NotFoundException('Follow-up cadence step not found.');
      }
      if (row.task_type !== 'WEEKLY_CHECK_IN' && update.recurrenceDays !== undefined) {
        throw new BadRequestException('Only weekly check-ins may define a recurrence interval.');
      }
      await this.audit.append(client, {
        actorUserId: actor.id,
        action: 'FOLLOW_UP_CADENCE_UPDATED',
        resourceType: 'FOLLOW_UP_CADENCE_STEP',
        resourceId: row.id,
        metadata: {
          code: row.code,
          dueOffsetHours: row.due_offset_hours,
          recurrenceDays: row.recurrence_days,
          isActive: row.is_active,
        },
      });
      return this.toStep(row);
    });
  }

  private toStep(row: CadenceStepRow): FollowUpCadenceStep {
    return {
      id: row.id,
      code: row.code,
      taskType: row.task_type,
      label: row.label,
      dueOffsetHours: row.due_offset_hours,
      ...(row.recurrence_days === null ? {} : { recurrenceDays: row.recurrence_days }),
      isActive: row.is_active,
      sortOrder: row.sort_order,
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

  private assertGlobalAdmin(actor: AuthenticatedActor): void {
    if (!actor.isGlobalAdmin || !actor.roles.includes('GLOBAL_ADMIN')) {
      throw new ForbiddenException('Global Admin access is required.');
    }
  }

  private auditSecret(): string {
    const secret = this.config.get<string>('AUDIT_CHAIN_SECRET');
    if (!secret || secret.startsWith('replace-with-') || secret.length < 32) {
      throw new Error('AUDIT_CHAIN_SECRET must be configured for follow-up cadence.');
    }
    return secret;
  }
}
