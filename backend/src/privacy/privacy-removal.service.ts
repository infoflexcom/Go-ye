import { BadRequestException, ForbiddenException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { PoolClient } from 'pg';
import { AuditService } from '../audit/audit.service.js';
import type { AuthenticatedActor } from '../authorization/authorization.types.js';
import { DatabaseService } from '../database/database.service.js';
import { FieldEncryptionService } from './field-encryption.service.js';
import type { PrivacyRemovalRequestFilterDto } from './dto/privacy-removal-request-filter.dto.js';
import type { RequestConvertRemovalDto } from './dto/request-convert-removal.dto.js';
import type { ResolveConvertRemovalDto } from './dto/resolve-convert-removal.dto.js';

export type PrivacyRemovalRequestStatus = 'PENDING' | 'ANONYMISED' | 'REJECTED';

interface RemovalRequestRow {
  id: string;
  convert_id: string;
  requested_by: string;
  reason_encrypted: Buffer | null;
  status: PrivacyRemovalRequestStatus;
  requested_at: Date;
  resolved_by: string | null;
  resolution_note_encrypted: Buffer | null;
  resolved_at: Date | null;
}

export interface PrivacyRemovalRequest {
  id: string;
  convertId: string;
  requestedBy: string;
  reason?: string;
  status: PrivacyRemovalRequestStatus;
  requestedAt: Date;
  resolvedBy?: string;
  resolutionNote?: string;
  resolvedAt?: Date;
}

const removalRequesterRoles = new Set([
  'COUNTRY_ADMIN',
  'REGION_LEADER',
  'PROVINCE_LEADER',
  'ZONE_LEADER',
  'AREA_LEADER',
  'PARISH_PASTOR',
  'SOUL_WINNER',
  'FOLLOW_UP_WORKER',
  'PRIVACY_OFFICER',
]);

@Injectable()
export class PrivacyRemovalService {
  constructor(
    private readonly database: DatabaseService,
    private readonly encryption: FieldEncryptionService,
    private readonly audit: AuditService,
    private readonly config: ConfigService,
  ) {}

  async requestRemoval(
    actor: AuthenticatedActor,
    convertId: string,
    dto: RequestConvertRemovalDto,
  ): Promise<{ requestId: string; status: 'PENDING' }> {
    this.assertRequester(actor);
    const reason = dto.reason === undefined ? undefined : this.requiredText(dto.reason, 'reason');
    return this.withActor(actor, async (client) => {
      const request = await client.query<{ id: string }>(
        'SELECT goye_request_convert_removal($1, $2, $3) AS id',
        [convertId, actor.id, reason ? this.encryption.encrypt(reason) : null],
      );
      const requestId = request.rows[0].id;
      await this.audit.append(client, {
        actorUserId: actor.id,
        action: 'CONVERT_REMOVAL_REQUESTED',
        resourceType: 'CONVERT_REMOVAL_REQUEST',
        resourceId: requestId,
        scopeUnitId: actor.homeUnitId,
        metadata: { convertId },
      });
      return { requestId, status: 'PENDING' };
    });
  }

  async listRequests(
    actor: AuthenticatedActor,
    filter: PrivacyRemovalRequestFilterDto,
  ): Promise<PrivacyRemovalRequest[]> {
    this.assertPrivacyOfficer(actor);
    return this.withPrivacyOfficer(actor, async (client) => {
      const requests = await client.query<RemovalRequestRow>(
        `SELECT id, convert_id, requested_by, reason_encrypted, status::text,
                requested_at, resolved_by, resolution_note_encrypted, resolved_at
         FROM convert_removal_requests
         WHERE ($1::privacy_removal_request_status IS NULL OR status = $1::privacy_removal_request_status)
         ORDER BY requested_at ASC, id ASC`,
        [filter.status ?? null],
      );
      return requests.rows.map((request) => this.toRequest(request));
    });
  }

  async resolve(
    actor: AuthenticatedActor,
    requestId: string,
    dto: ResolveConvertRemovalDto,
  ): Promise<{ convertId: string; status: PrivacyRemovalRequestStatus }> {
    this.assertPrivacyOfficer(actor);
    const note = dto.note === undefined ? undefined : this.requiredText(dto.note, 'note');
    return this.withPrivacyOfficer(actor, async (client) => {
      const resolved = await client.query<{
        convert_id: string;
        request_status: PrivacyRemovalRequestStatus;
      }>(
        `SELECT convert_id, request_status::text
         FROM goye_resolve_convert_removal($1, $2::privacy_removal_resolution, $3, $4, $5)`,
        [
          requestId,
          dto.outcome,
          actor.id,
          this.encryption.encrypt('Removed convert'),
          note ? this.encryption.encrypt(note) : null,
        ],
      );
      const result = resolved.rows[0];
      await this.audit.append(client, {
        actorUserId: actor.id,
        action:
          dto.outcome === 'ANONYMISE' ? 'CONVERT_REMOVAL_ANONYMISED' : 'CONVERT_REMOVAL_REJECTED',
        resourceType: 'CONVERT_REMOVAL_REQUEST',
        resourceId: requestId,
        scopeUnitId: actor.homeUnitId,
        metadata: { convertId: result.convert_id },
      });
      return { convertId: result.convert_id, status: result.request_status };
    });
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
        isPrivacyOfficer: actor.roles.includes('PRIVACY_OFFICER'),
        auditSecret: this.auditSecret(),
      },
      callback,
    );
  }

  private async withPrivacyOfficer<T>(
    actor: AuthenticatedActor,
    callback: (client: PoolClient) => Promise<T>,
  ): Promise<T> {
    return this.database.withActor(
      {
        userId: actor.id,
        homePath: actor.homePath,
        isGlobalAdmin: actor.isGlobalAdmin,
        isPrivacyOfficer: true,
        auditSecret: this.auditSecret(),
      },
      callback,
    );
  }

  private assertRequester(actor: AuthenticatedActor): void {
    if (actor.isGlobalAdmin || actor.roles.some((role) => removalRequesterRoles.has(role))) {
      return;
    }
    throw new ForbiddenException('The active role cannot request convert removal.');
  }

  private assertPrivacyOfficer(actor: AuthenticatedActor): void {
    if (actor.isGlobalAdmin || actor.roles.includes('PRIVACY_OFFICER')) {
      return;
    }
    throw new ForbiddenException('A Privacy Officer or Global Admin is required.');
  }

  private auditSecret(): string {
    const secret = this.config.get<string>('AUDIT_CHAIN_SECRET');
    if (!secret || secret.startsWith('replace-with-') || secret.length < 32) {
      throw new BadRequestException('Audit chain is not configured.');
    }
    return secret;
  }

  private requiredText(value: string, field: string): string {
    const normalized = value.trim();
    if (!normalized) {
      throw new BadRequestException(`${field} must not be blank.`);
    }
    return normalized;
  }

  private toRequest(row: RemovalRequestRow): PrivacyRemovalRequest {
    return {
      id: row.id,
      convertId: row.convert_id,
      requestedBy: row.requested_by,
      ...(row.reason_encrypted ? { reason: this.encryption.decrypt(row.reason_encrypted) } : {}),
      status: row.status,
      requestedAt: row.requested_at,
      ...(row.resolved_by ? { resolvedBy: row.resolved_by } : {}),
      ...(row.resolution_note_encrypted
        ? { resolutionNote: this.encryption.decrypt(row.resolution_note_encrypted) }
        : {}),
      ...(row.resolved_at ? { resolvedAt: row.resolved_at } : {}),
    };
  }
}
