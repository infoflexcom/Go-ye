import { Controller, Get, Param, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOkResponse, ApiOperation, ApiTags } from '@nestjs/swagger';
import type { AuthenticatedActor } from '../authorization/authorization.types.js';
import { CurrentActor } from '../authorization/current-actor.decorator.js';
import { JwtAuthGuard } from '../authorization/jwt-auth.guard.js';
import { RequireRoles } from '../authorization/roles.decorator.js';
import { RolesGuard } from '../authorization/roles.guard.js';
import { AdminReportsService } from './admin-reports.service.js';
import {
  AdminConvertDrillDownFilterDto,
  AdminReportFilterDto,
} from './dto/admin-report-filter.dto.js';

@ApiTags('global administration reports')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, RolesGuard)
@RequireRoles('GLOBAL_ADMIN')
@Controller('admin/reports')
export class AdminReportsController {
  constructor(private readonly reports: AdminReportsService) {}

  @Get('countries')
  @ApiOperation({ summary: 'List all countries and their filtered convert totals' })
  listCountries(@CurrentActor() actor: AuthenticatedActor, @Query() filter: AdminReportFilterDto) {
    return this.reports.listCountries(actor, filter);
  }

  @Get('grand-total')
  @ApiOperation({ summary: 'Read the filtered grand total across all countries exactly once' })
  grandTotal(@CurrentActor() actor: AuthenticatedActor, @Query() filter: AdminReportFilterDto) {
    return this.reports.grandTotal(actor, filter);
  }

  @Get('countries/:countryId/regions')
  @ApiOperation({ summary: 'Read per-region filtered convert totals for one selected country' })
  regions(
    @CurrentActor() actor: AuthenticatedActor,
    @Param('countryId') countryId: string,
    @Query() filter: AdminReportFilterDto,
  ) {
    return this.reports.listRegions(actor, countryId, filter);
  }

  @Get('countries/:countryId/total')
  @ApiOperation({ summary: 'Read one selected country filtered total' })
  countryTotal(
    @CurrentActor() actor: AuthenticatedActor,
    @Param('countryId') countryId: string,
    @Query() filter: AdminReportFilterDto,
  ) {
    return this.reports.countryTotal(actor, countryId, filter);
  }

  @Get('countries/:countryId/converts')
  @ApiOperation({ summary: 'Drill down from a selected country to its non-merged converts' })
  @ApiOkResponse({
    description: 'Paginated converted detail; filtered totals exclude merged duplicates.',
  })
  drillDown(
    @CurrentActor() actor: AuthenticatedActor,
    @Param('countryId') countryId: string,
    @Query() filter: AdminConvertDrillDownFilterDto,
  ) {
    return this.reports.drillDownCountry(actor, countryId, filter);
  }
}
