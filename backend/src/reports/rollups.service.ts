import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { AuthenticatedActor } from '../authorization/authorization.types.js';
import type { ConvertStage } from '../converts/converts.service.js';
import { DatabaseService } from '../database/database.service.js';
import type { RollupFilterDto } from './dto/rollup-filter.dto.js';

const reportingRoles = new Set([
  'COUNTRY_ADMIN',
  'REGION_LEADER',
  'PROVINCE_LEADER',
  'ZONE_LEADER',
  'AREA_LEADER',
  'PARISH_PASTOR',
  'SOUL_WINNER',
  'FOLLOW_UP_WORKER',
]);

export interface UnitRollup {
  unitId: string;
  total: number;
  byStage: Partial<Record<ConvertStage, number>>;
}

@Injectable()
export class RollupsService {
  constructor(private readonly database: DatabaseService) {}

  async getUnitRollup(
    actor: AuthenticatedActor,
    unitId: string,
    filter: RollupFilterDto,
  ): Promise<UnitRollup> {
    this.assertReportingAccess(actor);
    this.assertDateRange(filter);
    return this.database.withActor(
      {
        userId: actor.id,
        homePath: actor.homePath,
        isGlobalAdmin: actor.isGlobalAdmin,
      },
      async (client) => {
        const unit = await client.query<{ id: string }>('SELECT id FROM org_units WHERE id = $1', [
          unitId,
        ]);
        if (!unit.rows[0]) {
          throw new NotFoundException('Organisation unit not found.');
        }
        const summaries = await client.query<{ stage: ConvertStage; total: string }>(
          `SELECT stage::text, sum(total_count)::text AS total
           FROM convert_rollup_daily
           WHERE org_unit_id = $1
             AND ($2::date IS NULL OR report_date >= $2::date)
             AND ($3::date IS NULL OR report_date <= $3::date)
             AND ($4::convert_stage IS NULL OR stage = $4::convert_stage)
           GROUP BY stage`,
          [unitId, filter.startDate ?? null, filter.endDate ?? null, filter.stage ?? null],
        );
        const byStage = Object.fromEntries(
          summaries.rows.map((row) => [row.stage, Number(row.total)]),
        ) as Partial<Record<ConvertStage, number>>;
        return {
          unitId,
          total: Object.values(byStage).reduce((sum, value) => sum + value, 0),
          byStage,
        };
      },
    );
  }

  private assertReportingAccess(actor: AuthenticatedActor): void {
    if (actor.isGlobalAdmin) {
      return;
    }
    if (!actor.homePath || !actor.roles.some((role) => reportingRoles.has(role))) {
      throw new ForbiddenException('The active role does not permit convert reporting.');
    }
  }

  private assertDateRange(filter: RollupFilterDto): void {
    if (filter.startDate && filter.endDate && filter.startDate > filter.endDate) {
      throw new BadRequestException('startDate must be on or before endDate.');
    }
  }
}
