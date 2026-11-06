import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHmac } from 'node:crypto';
import type { PoolClient } from 'pg';
import { AuditService } from '../audit/audit.service.js';
import type { AuthenticatedActor } from '../authorization/authorization.types.js';
import { normalizeIdentity } from '../auth/auth.identity.js';
import { DatabaseService } from '../database/database.service.js';
import { FieldEncryptionService } from '../privacy/field-encryption.service.js';
import type { AddConvertActivityDto } from './dto/add-convert-activity.dto.js';
import type { AdvanceConvertStageDto } from './dto/advance-convert-stage.dto.js';
import type { AssignConvertDto } from './dto/assign-convert.dto.js';
import type { DetectDuplicateDto } from './dto/detect-duplicate.dto.js';
import type { MergeConvertDto } from './dto/merge-convert.dto.js';
import type { CreateConvertDto } from './dto/create-convert.dto.js';
import type { UpdateConvertDto } from './dto/update-convert.dto.js';

export type ConvertStage =
  'NEW_CONVERT' | 'BELIEVERS_CLASS' | 'BAPTISMAL_CLASS' | 'BAPTISED' | 'FULLY_PLANTED';

export interface ConvertTimelineEvent {
  id: string;
  eventType: string;
  fromStage?: ConvertStage;
  toStage?: ConvertStage;
  note?: string;
  actorUserId: string;
  occurredAt: Date;
}

const convertWorkerRoles = new Set([
  'COUNTRY_ADMIN',
  'REGION_LEADER',
  'PROVINCE_LEADER',
  'ZONE_LEADER',
  'AREA_LEADER',
  'PARISH_PASTOR',
  'SOUL_WINNER',
  'FOLLOW_UP_WORKER',
]);

type ConvertDatabaseRow = {
  id: string;
  full_name_encrypted: Buffer;
  phone_encrypted: Buffer | null;
  address_encrypted: Buffer | null;
  registered_at_unit_id: string;
  registered_by: string;
  parish_id: string | null;
  assigned_at: Date | null;
  assigned_by: string | null;
  merged_into_id: string | null;
  merged_at: Date | null;
  merged_by: string | null;
  stage: ConvertStage;
  stage_changed_at: Date;
  consent_version: string;
  consent_method: 'VERBAL' | 'DIGITAL' | 'WRITTEN';
  consent_captured_at: Date;
  consent_captured_by: string;
  created_at: Date;
  updated_at: Date;
};

type TimelineDatabaseRow = {
  id: string;
  event_type: string;
  from_stage: ConvertStage | null;
  to_stage: ConvertStage | null;
  note_encrypted: Buffer | null;
  actor_user_id: string;
  occurred_at: Date;
};

export interface ConvertRecord {
  id: string;
  fullName: string;
  phone?: string;
  address?: string;
  registeredAtUnitId: string;
  registeredBy: string;
  parishId?: string;
  assignedAt?: Date;
  assignedBy?: string;
  mergedIntoId?: string;
  mergedAt?: Date;
  mergedBy?: string;
  stage: ConvertStage;
  stageChangedAt: Date;
  consent: {
    version: string;
    method: 'VERBAL' | 'DIGITAL' | 'WRITTEN';
    capturedAt: Date;
    capturedBy: string;
  };
  createdAt: Date;
  updatedAt: Date;
}

@Injectable()
export class ConvertsService {
  constructor(
    private readonly database: DatabaseService,
    private readonly encryption: FieldEncryptionService,
    private readonly audit: AuditService,
    private readonly config: ConfigService,
  ) {}

  async create(actor: AuthenticatedActor, dto: CreateConvertDto): Promise<ConvertRecord> {
    this.assertConvertWorker(actor);
    if (dto.consent.granted !== true) {
      throw new BadRequestException(
        'Consent must be affirmatively granted before a convert can be saved.',
      );
    }
    const registeredAtUnitId = dto.registeredAtUnitId ?? actor.homeUnitId;
    if (!registeredAtUnitId) {
      throw new BadRequestException('A registration unit is required for a Global Admin.');
    }
    if (!actor.isGlobalAdmin && registeredAtUnitId !== actor.homeUnitId) {
      throw new ForbiddenException('Converts can only be registered at the actor home unit.');
    }
    const fullName = this.requiredText(dto.fullName, 'fullName');
    const phone = dto.phone ? this.normalizedPhone(dto.phone) : undefined;
    const phoneLookupHash = phone ? this.phoneLookupHash(phone) : undefined;
    const address = dto.address ? this.requiredText(dto.address, 'address') : undefined;

    return this.withConvertActor(actor, async (client) => {
      const registrationUnit = await client.query<{ id: string; type: string }>(
        'SELECT id, type::text FROM org_units WHERE id = $1 AND is_active',
        [registeredAtUnitId],
      );
      if (!registrationUnit.rows[0]) {
        throw new NotFoundException('Active registration unit not found.');
      }
      const result = await client.query<ConvertDatabaseRow>(
        `INSERT INTO converts (
          full_name_encrypted, phone_encrypted, address_encrypted, phone_lookup_hash,
          registered_at_unit_id, registered_by,
          consent_granted, consent_version, consent_method, consent_captured_by
        ) VALUES ($1, $2, $3, $4, $5, $6, true, $7, $8::consent_capture_method, $6)
        RETURNING ${this.convertColumns()}`,
        [
          this.encryption.encrypt(fullName),
          phone ? this.encryption.encrypt(phone) : null,
          address ? this.encryption.encrypt(address) : null,
          phoneLookupHash ?? null,
          registeredAtUnitId,
          actor.id,
          this.requiredText(dto.consent.version, 'consent.version'),
          dto.consent.method,
        ],
      );
      let row = result.rows[0];
      if (registrationUnit.rows[0].type === 'PARISH') {
        await this.assignToParishInTransaction(client, row.id, registeredAtUnitId, actor.id);
        row = await this.getInTransaction(client, row.id);
      }
      await this.audit.append(client, {
        actorUserId: actor.id,
        action: 'CONVERT_REGISTERED_WITH_CONSENT',
        resourceType: 'CONVERT',
        resourceId: row.id,
        scopeUnitId: row.registered_at_unit_id,
        metadata: {
          registrationUnitId: row.registered_at_unit_id,
          consentVersion: row.consent_version,
          consentMethod: row.consent_method,
        },
      });
      await this.appendTimelineEvent(client, row.id, 'REGISTERED', actor.id);
      if (row.parish_id) {
        await this.appendTimelineEvent(client, row.id, 'PARISH_ASSIGNED', actor.id);
        await this.audit.append(client, {
          actorUserId: actor.id,
          action: 'CONVERT_ASSIGNED_TO_PARISH',
          resourceType: 'CONVERT',
          resourceId: row.id,
          scopeUnitId: row.parish_id,
          metadata: { parishId: row.parish_id, automaticFromParishRegistration: true },
        });
      }
      return this.toRecord(row);
    });
  }

  async get(actor: AuthenticatedActor, id: string): Promise<ConvertRecord> {
    this.assertConvertWorker(actor);
    return this.withConvertActor(actor, async (client) => {
      const result = await client.query<ConvertDatabaseRow>(
        `SELECT ${this.convertColumns()} FROM converts WHERE id = $1`,
        [id],
      );
      const row = result.rows[0];
      if (!row) {
        throw new NotFoundException('Convert not found.');
      }
      return this.toRecord(row);
    });
  }

  async detectDuplicates(
    actor: AuthenticatedActor,
    dto: DetectDuplicateDto,
  ): Promise<ConvertRecord[]> {
    this.assertConvertWorker(actor);
    const hash = this.phoneLookupHash(this.normalizedPhone(dto.phone));
    return this.withConvertActor(actor, async (client) => {
      const result = await client.query<ConvertDatabaseRow>(
        `SELECT ${this.convertColumns()} FROM converts
         WHERE phone_lookup_hash = $1 AND merged_into_id IS NULL
         ORDER BY created_at ASC`,
        [hash],
      );
      return result.rows.map((row) => this.toRecord(row));
    });
  }

  async merge(
    actor: AuthenticatedActor,
    targetConvertId: string,
    dto: MergeConvertDto,
  ): Promise<ConvertRecord> {
    this.assertConvertWorker(actor);
    return this.withConvertActor(actor, async (client) => {
      await client.query('SELECT * FROM goye_merge_converts($1, $2, $3)', [
        dto.duplicateConvertId,
        targetConvertId,
        actor.id,
      ]);
      const target = await this.getInTransaction(client, targetConvertId);
      await this.appendTimelineEvent(
        client,
        dto.duplicateConvertId,
        'MERGED_INTO',
        actor.id,
        undefined,
        { canonicalConvertId: targetConvertId },
      );
      await this.appendTimelineEvent(
        client,
        targetConvertId,
        'MERGED_DUPLICATE',
        actor.id,
        undefined,
        { duplicateConvertId: dto.duplicateConvertId },
      );
      await this.audit.append(client, {
        actorUserId: actor.id,
        action: 'CONVERT_MERGED',
        resourceType: 'CONVERT',
        resourceId: targetConvertId,
        scopeUnitId: target.parish_id ?? target.registered_at_unit_id,
        metadata: { mergedDuplicateConvertId: dto.duplicateConvertId },
      });
      return this.toRecord(target);
    });
  }

  async advanceStage(
    actor: AuthenticatedActor,
    id: string,
    dto: AdvanceConvertStageDto,
  ): Promise<ConvertRecord> {
    this.assertConvertWorker(actor);
    const note = dto.note === undefined ? undefined : this.requiredText(dto.note, 'note');
    return this.withConvertActor(actor, async (client) => {
      await client.query(
        'SELECT * FROM goye_advance_convert_stage($1, $2::convert_stage, $3, $4)',
        [id, dto.stage, actor.id, note ? this.encryption.encrypt(note) : null],
      );
      const row = await this.getInTransaction(client, id);
      await this.audit.append(client, {
        actorUserId: actor.id,
        action: 'CONVERT_STAGE_ADVANCED',
        resourceType: 'CONVERT',
        resourceId: row.id,
        scopeUnitId: row.parish_id ?? row.registered_at_unit_id,
        metadata: { stage: row.stage },
      });
      return this.toRecord(row);
    });
  }

  async addActivity(
    actor: AuthenticatedActor,
    id: string,
    dto: AddConvertActivityDto,
  ): Promise<ConvertTimelineEvent> {
    this.assertConvertWorker(actor);
    const note = this.requiredText(dto.note, 'note');
    return this.withConvertActor(actor, async (client) => {
      await this.appendTimelineEvent(client, id, 'NOTE', actor.id, note);
      const result = await client.query<TimelineDatabaseRow>(
        `SELECT id, event_type::text, from_stage::text, to_stage::text, note_encrypted, actor_user_id, occurred_at
         FROM convert_timeline_events WHERE convert_id = $1 ORDER BY event_sequence DESC LIMIT 1`,
        [id],
      );
      return this.toTimelineEvent(result.rows[0]);
    });
  }

  async timeline(actor: AuthenticatedActor, id: string): Promise<ConvertTimelineEvent[]> {
    this.assertConvertWorker(actor);
    return this.withConvertActor(actor, async (client) => {
      const result = await client.query<TimelineDatabaseRow>(
        `SELECT id, event_type::text, from_stage::text, to_stage::text, note_encrypted, actor_user_id, occurred_at
         FROM convert_timeline_events WHERE convert_id = $1 ORDER BY event_sequence ASC`,
        [id],
      );
      if (result.rows.length === 0) {
        const convert = await client.query<{ id: string }>(
          'SELECT id FROM converts WHERE id = $1',
          [id],
        );
        if (!convert.rows[0]) {
          throw new NotFoundException('Convert not found.');
        }
      }
      return result.rows.map((row) => this.toTimelineEvent(row));
    });
  }

  async listUnassigned(
    actor: AuthenticatedActor,
  ): Promise<(ConvertRecord & { unassignedAgeDays: number })[]> {
    this.assertConvertWorker(actor);
    return this.withConvertActor(actor, async (client) => {
      const result = await client.query<ConvertDatabaseRow & { unassigned_age_days: number }>(
        `SELECT ${this.convertColumns()},
                floor(extract(epoch FROM (now() - created_at)) / 86400)::integer AS unassigned_age_days
         FROM converts
         WHERE parish_id IS NULL AND merged_into_id IS NULL
         ORDER BY created_at ASC`,
      );
      return result.rows.map((row) => ({
        ...this.toRecord(row),
        unassignedAgeDays: row.unassigned_age_days,
      }));
    });
  }

  async assignToParish(
    actor: AuthenticatedActor,
    id: string,
    dto: AssignConvertDto,
  ): Promise<ConvertRecord> {
    this.assertConvertWorker(actor);
    return this.withConvertActor(actor, async (client) => {
      await this.assignToParishInTransaction(client, id, dto.parishId, actor.id);
      const row = await this.getInTransaction(client, id);
      await this.appendTimelineEvent(client, row.id, 'PARISH_ASSIGNED', actor.id);
      await this.audit.append(client, {
        actorUserId: actor.id,
        action: 'CONVERT_ASSIGNED_TO_PARISH',
        resourceType: 'CONVERT',
        resourceId: row.id,
        scopeUnitId: row.parish_id ?? undefined,
        metadata: { parishId: row.parish_id, automaticFromParishRegistration: false },
      });
      return this.toRecord(row);
    });
  }

  async update(
    actor: AuthenticatedActor,
    id: string,
    dto: UpdateConvertDto,
  ): Promise<ConvertRecord> {
    this.assertConvertWorker(actor);
    if (dto.fullName === undefined && dto.phone === undefined && dto.address === undefined) {
      throw new BadRequestException('At least one editable convert field is required.');
    }
    const fullName =
      dto.fullName === undefined ? undefined : this.requiredText(dto.fullName, 'fullName');
    const phone = dto.phone === undefined ? undefined : this.normalizedPhone(dto.phone);
    const phoneLookupHash = phone === undefined ? undefined : this.phoneLookupHash(phone);
    const address =
      dto.address === undefined ? undefined : this.requiredText(dto.address, 'address');

    return this.withConvertActor(actor, async (client) => {
      const updated = await client.query<ConvertDatabaseRow>(
        `UPDATE converts
         SET full_name_encrypted = CASE WHEN $1::boolean THEN $2 ELSE full_name_encrypted END,
             phone_encrypted = CASE WHEN $3::boolean THEN $4 ELSE phone_encrypted END,
             phone_lookup_hash = CASE WHEN $3::boolean THEN $5 ELSE phone_lookup_hash END,
             address_encrypted = CASE WHEN $6::boolean THEN $7 ELSE address_encrypted END
         WHERE id = $8
         RETURNING ${this.convertColumns()}`,
        [
          fullName !== undefined,
          fullName ? this.encryption.encrypt(fullName) : null,
          phone !== undefined,
          phone ? this.encryption.encrypt(phone) : null,
          phoneLookupHash ?? null,
          address !== undefined,
          address ? this.encryption.encrypt(address) : null,
          id,
        ],
      );
      const row = updated.rows[0];
      if (!row) {
        throw new NotFoundException('Convert not found.');
      }
      await this.audit.append(client, {
        actorUserId: actor.id,
        action: 'CONVERT_UPDATED',
        resourceType: 'CONVERT',
        resourceId: row.id,
        scopeUnitId: row.registered_at_unit_id,
        metadata: {
          fullNameChanged: fullName !== undefined,
          phoneChanged: phone !== undefined,
          addressChanged: address !== undefined,
        },
      });
      return this.toRecord(row);
    });
  }

  private async appendTimelineEvent(
    client: PoolClient,
    convertId: string,
    eventType: 'REGISTERED' | 'PARISH_ASSIGNED' | 'NOTE' | 'MERGED_INTO' | 'MERGED_DUPLICATE',
    actorId: string,
    note?: string,
    metadata: Record<string, string> = {},
  ): Promise<void> {
    await client.query(
      `SELECT goye_append_convert_timeline_event(
        $1, $2::convert_timeline_event_type, $3, $4, $5::jsonb
      )`,
      [
        convertId,
        eventType,
        actorId,
        note ? this.encryption.encrypt(note) : null,
        JSON.stringify(metadata),
      ],
    );
  }

  private async assignToParishInTransaction(
    client: PoolClient,
    convertId: string,
    parishId: string,
    actorId: string,
  ): Promise<void> {
    await client.query('SELECT * FROM goye_assign_convert_to_parish($1, $2, $3)', [
      convertId,
      parishId,
      actorId,
    ]);
  }

  private async getInTransaction(client: PoolClient, id: string): Promise<ConvertDatabaseRow> {
    const result = await client.query<ConvertDatabaseRow>(
      `SELECT ${this.convertColumns()} FROM converts WHERE id = $1`,
      [id],
    );
    const row = result.rows[0];
    if (!row) {
      throw new NotFoundException('Convert not found.');
    }
    return row;
  }

  private async withConvertActor<T>(
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

  private assertConvertWorker(actor: AuthenticatedActor): void {
    if (actor.isGlobalAdmin) {
      return;
    }
    if (
      !actor.homeUnitId ||
      !actor.homePath ||
      !actor.roles.some((role) => convertWorkerRoles.has(role))
    ) {
      throw new ForbiddenException('The active role and home unit do not permit convert work.');
    }
  }

  private auditSecret(): string {
    const secret = this.config.get<string>('AUDIT_CHAIN_SECRET');
    if (!secret || secret.startsWith('replace-with-')) {
      throw new Error('AUDIT_CHAIN_SECRET must be configured for convert operations.');
    }
    return secret;
  }

  private phoneLookupHash(phone: string): string {
    const pepper = this.config.get<string>('PII_LOOKUP_PEPPER');
    if (!pepper || pepper.startsWith('replace-with-')) {
      throw new Error('PII_LOOKUP_PEPPER must be configured for duplicate detection.');
    }
    return createHmac('sha256', pepper).update(phone).digest('hex');
  }

  private normalizedPhone(value: string): string {
    const normalized = normalizeIdentity(value);
    if (normalized.channel !== 'PHONE') {
      throw new BadRequestException('phone must be an E.164 telephone number.');
    }
    return normalized.destination;
  }

  private requiredText(value: string, field: string): string {
    const normalized = value.trim();
    if (!normalized) {
      throw new BadRequestException(`${field} must not be blank.`);
    }
    return normalized;
  }

  private convertColumns(): string {
    return `id, full_name_encrypted, phone_encrypted, address_encrypted,
      registered_at_unit_id, registered_by, parish_id, assigned_at, assigned_by,
      merged_into_id, merged_at, merged_by, stage::text, stage_changed_at,
      consent_version, consent_method::text, consent_captured_at, consent_captured_by,
      created_at, updated_at`;
  }

  private toTimelineEvent(row: TimelineDatabaseRow | undefined): ConvertTimelineEvent {
    if (!row) {
      throw new NotFoundException('Convert activity not found.');
    }
    return {
      id: row.id,
      eventType: row.event_type,
      ...(row.from_stage ? { fromStage: row.from_stage } : {}),
      ...(row.to_stage ? { toStage: row.to_stage } : {}),
      ...(row.note_encrypted ? { note: this.encryption.decrypt(row.note_encrypted) } : {}),
      actorUserId: row.actor_user_id,
      occurredAt: row.occurred_at,
    };
  }

  private toRecord(row: ConvertDatabaseRow): ConvertRecord {
    return {
      id: row.id,
      fullName: this.encryption.decrypt(row.full_name_encrypted),
      ...(row.phone_encrypted ? { phone: this.encryption.decrypt(row.phone_encrypted) } : {}),
      ...(row.address_encrypted ? { address: this.encryption.decrypt(row.address_encrypted) } : {}),
      registeredAtUnitId: row.registered_at_unit_id,
      registeredBy: row.registered_by,
      ...(row.parish_id ? { parishId: row.parish_id } : {}),
      ...(row.assigned_at ? { assignedAt: row.assigned_at } : {}),
      ...(row.assigned_by ? { assignedBy: row.assigned_by } : {}),
      ...(row.merged_into_id ? { mergedIntoId: row.merged_into_id } : {}),
      ...(row.merged_at ? { mergedAt: row.merged_at } : {}),
      ...(row.merged_by ? { mergedBy: row.merged_by } : {}),
      stage: row.stage,
      stageChangedAt: row.stage_changed_at,
      consent: {
        version: row.consent_version,
        method: row.consent_method,
        capturedAt: row.consent_captured_at,
        capturedBy: row.consent_captured_by,
      },
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }
}
