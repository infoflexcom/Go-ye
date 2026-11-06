import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { PoolClient } from 'pg';
import { AuditService } from '../audit/audit.service.js';
import { FieldEncryptionService } from '../privacy/field-encryption.service.js';
import type { AuthenticatedActor } from '../authorization/authorization.types.js';
import { DatabaseService } from '../database/database.service.js';
import type { ConvertStage } from '../converts/converts.service.js';
import type {
  AdminConvertDrillDownFilterDto,
  AdminReportFilterDto,
} from './dto/admin-report-filter.dto.js';

interface SummaryRow {
  id: string;
  code: string;
  name: string;
  total: string;
}

interface DrillDownRow {
  id: string;
  full_name_encrypted: Buffer;
  phone_encrypted: Buffer | null;
  registered_at_unit_id: string;
  registered_by: string;
  parish_id: string | null;
  stage: ConvertStage;
  created_at: Date;
}

export interface AdminConvertDrillDown {
  id: string;
  fullName: string;
  phone?: string;
  registeredAtUnitId: string;
  registeredBy: string;
  parishId?: string;
  stage: ConvertStage;
  createdAt: Date;
}

@Injectable()
export class AdminReportsService {
  constructor(
    private readonly database: DatabaseService,
    private readonly encryption: FieldEncryptionService,
    private readonly config: ConfigService,
    private readonly audit: AuditService,
  ) {}

  async listCountries(actor: AuthenticatedActor, filter: AdminReportFilterDto) {
    this.assertGlobalAdmin(actor);
    this.assertDateRange(filter);
    return this.withGlobalAdmin(actor, async (client) => {
      const result = await client.query<SummaryRow>(
        `SELECT unit.id, unit.code, unit.name, COALESCE(sum(summary.total_count), 0)::text AS total
         FROM org_units unit
         LEFT JOIN convert_rollup_daily summary
           ON summary.org_unit_id = unit.id
          AND ($1::date IS NULL OR summary.report_date >= $1::date)
          AND ($2::date IS NULL OR summary.report_date <= $2::date)
          AND ($3::convert_stage IS NULL OR summary.stage = $3::convert_stage)
         WHERE unit.type = 'COUNTRY'
         GROUP BY unit.id, unit.code, unit.name
         ORDER BY unit.name, unit.code`,
        [filter.startDate ?? null, filter.endDate ?? null, filter.stage ?? null],
      );
      return result.rows.map((row) => ({ ...this.summary(row) }));
    });
  }

  async listRegions(actor: AuthenticatedActor, countryId: string, filter: AdminReportFilterDto) {
    this.assertGlobalAdmin(actor);
    this.assertDateRange(filter);
    return this.withGlobalAdmin(actor, async (client) => {
      await this.assertCountry(client, countryId);
      const result = await client.query<SummaryRow>(
        `SELECT unit.id, unit.code, unit.name, COALESCE(sum(summary.total_count), 0)::text AS total
         FROM org_units unit
         LEFT JOIN convert_rollup_daily summary
           ON summary.org_unit_id = unit.id
          AND ($2::date IS NULL OR summary.report_date >= $2::date)
          AND ($3::date IS NULL OR summary.report_date <= $3::date)
          AND ($4::convert_stage IS NULL OR summary.stage = $4::convert_stage)
         WHERE unit.parent_id = $1 AND unit.type = 'REGION'
         GROUP BY unit.id, unit.code, unit.name
         ORDER BY unit.name, unit.code`,
        [countryId, filter.startDate ?? null, filter.endDate ?? null, filter.stage ?? null],
      );
      return result.rows.map((row) => this.summary(row));
    });
  }

  async countryTotal(actor: AuthenticatedActor, countryId: string, filter: AdminReportFilterDto) {
    this.assertGlobalAdmin(actor);
    this.assertDateRange(filter);
    return this.withGlobalAdmin(actor, async (client) => {
      const country = await this.assertCountry(client, countryId);
      const total = await this.totalForUnit(client, countryId, filter);
      return { countryId, countryCode: country.code, total };
    });
  }

  async grandTotal(actor: AuthenticatedActor, filter: AdminReportFilterDto) {
    this.assertGlobalAdmin(actor);
    this.assertDateRange(filter);
    return this.withGlobalAdmin(actor, async (client) => {
      const result = await client.query<{ total: string }>(
        `SELECT COALESCE(sum(summary.total_count), 0)::text AS total
         FROM convert_rollup_daily summary
         JOIN org_units unit ON unit.id = summary.org_unit_id
         WHERE unit.type = 'COUNTRY'
           AND ($1::date IS NULL OR summary.report_date >= $1::date)
           AND ($2::date IS NULL OR summary.report_date <= $2::date)
           AND ($3::convert_stage IS NULL OR summary.stage = $3::convert_stage)`,
        [filter.startDate ?? null, filter.endDate ?? null, filter.stage ?? null],
      );
      return { total: Number(result.rows[0].total) };
    });
  }

  async drillDownCountry(
    actor: AuthenticatedActor,
    countryId: string,
    filter: AdminConvertDrillDownFilterDto,
  ): Promise<{ total: number; items: AdminConvertDrillDown[] }> {
    this.assertGlobalAdmin(actor);
    this.assertDateRange(filter);
    return this.withGlobalAdmin(actor, async (client) => {
      const country = await this.assertCountry(client, countryId);
      const offset = filter.offset ?? 0;
      const limit = filter.limit ?? 50;
      const count = await client.query<{ total: string }>(
        `SELECT count(*)::text AS total
         FROM converts convert
         JOIN org_units registration_unit ON registration_unit.id = convert.registered_at_unit_id
         WHERE registration_unit.path <@ $1::ltree
           AND convert.merged_into_id IS NULL
           AND convert.privacy_status = 'ACTIVE'
           AND ($2::date IS NULL OR convert.created_at::date >= $2::date)
           AND ($3::date IS NULL OR convert.created_at::date <= $3::date)
           AND ($4::convert_stage IS NULL OR convert.stage = $4::convert_stage)`,
        [country.path, filter.startDate ?? null, filter.endDate ?? null, filter.stage ?? null],
      );
      const converts = await client.query<DrillDownRow>(
        `SELECT convert.id, convert.full_name_encrypted, convert.phone_encrypted,
                convert.registered_at_unit_id, convert.registered_by, convert.parish_id,
                convert.stage::text, convert.created_at
         FROM converts convert
         JOIN org_units registration_unit ON registration_unit.id = convert.registered_at_unit_id
         WHERE registration_unit.path <@ $1::ltree
           AND convert.merged_into_id IS NULL
           AND convert.privacy_status = 'ACTIVE'
           AND ($2::date IS NULL OR convert.created_at::date >= $2::date)
           AND ($3::date IS NULL OR convert.created_at::date <= $3::date)
           AND ($4::convert_stage IS NULL OR convert.stage = $4::convert_stage)
         ORDER BY convert.created_at DESC, convert.id DESC
         OFFSET $5 LIMIT $6`,
        [
          country.path,
          filter.startDate ?? null,
          filter.endDate ?? null,
          filter.stage ?? null,
          offset,
          limit,
        ],
      );
      const total = Number(count.rows[0].total);
      await this.audit.append(client, {
        actorUserId: actor.id,
        action: 'GLOBAL_ADMIN_CONVERT_DRILL_DOWN_READ',
        resourceType: 'CONVERT_REPORT',
        scopeUnitId: countryId,
        metadata: {
          total,
          offset,
          limit,
          stage: filter.stage ?? null,
          startDate: filter.startDate ?? null,
          endDate: filter.endDate ?? null,
        },
      });
      return {
        total,
        items: converts.rows.map((row) => ({
          id: row.id,
          fullName: this.encryption.decrypt(row.full_name_encrypted),
          ...(row.phone_encrypted ? { phone: this.encryption.decrypt(row.phone_encrypted) } : {}),
          registeredAtUnitId: row.registered_at_unit_id,
          registeredBy: row.registered_by,
          ...(row.parish_id ? { parishId: row.parish_id } : {}),
          stage: row.stage,
          createdAt: row.created_at,
        })),
      };
    });
  }

  private async withGlobalAdmin<T>(
    actor: AuthenticatedActor,
    callback: (client: PoolClient) => Promise<T>,
  ): Promise<T> {
    return this.database.withActor<T>(
      { userId: actor.id, isGlobalAdmin: true, auditSecret: this.auditSecret() },
      callback,
    );
  }

  private auditSecret(): string {
    const secret = this.config.get<string>('AUDIT_CHAIN_SECRET');
    if (!secret || secret.startsWith('replace-with-') || secret.length < 32) {
      throw new BadRequestException('Audit chain is not configured.');
    }
    return secret;
  }

  private assertGlobalAdmin(actor: AuthenticatedActor): void {
    if (!actor.isGlobalAdmin || !actor.roles.includes('GLOBAL_ADMIN')) {
      throw new ForbiddenException('Global Admin access is required.');
    }
  }

  private assertDateRange(filter: AdminReportFilterDto): void {
    if (filter.startDate && filter.endDate && filter.startDate > filter.endDate) {
      throw new BadRequestException('startDate must be on or before endDate.');
    }
  }

  private async assertCountry(client: PoolClient, id: string) {
    const result = await client.query<{ id: string; code: string; path: string }>(
      `SELECT id, code, path::text FROM org_units WHERE id = $1 AND type = 'COUNTRY'`,
      [id],
    );
    const country = result.rows[0];
    if (!country) {
      throw new NotFoundException('Country not found.');
    }
    return country;
  }

  private async totalForUnit(
    client: PoolClient,
    unitId: string,
    filter: AdminReportFilterDto,
  ): Promise<number> {
    const result = await client.query<{ total: string }>(
      `SELECT COALESCE(sum(total_count), 0)::text AS total
       FROM convert_rollup_daily
       WHERE org_unit_id = $1
         AND ($2::date IS NULL OR report_date >= $2::date)
         AND ($3::date IS NULL OR report_date <= $3::date)
         AND ($4::convert_stage IS NULL OR stage = $4::convert_stage)`,
      [unitId, filter.startDate ?? null, filter.endDate ?? null, filter.stage ?? null],
    );
    return Number(result.rows[0].total);
  }

  private summary(row: SummaryRow) {
    return { id: row.id, code: row.code, name: row.name, total: Number(row.total) };
  }
}
