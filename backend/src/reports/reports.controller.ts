import { Controller, Get, Param, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOkResponse, ApiOperation, ApiTags } from '@nestjs/swagger';
import type { AuthenticatedActor } from '../authorization/authorization.types.js';
import { CurrentActor } from '../authorization/current-actor.decorator.js';
import { JwtAuthGuard } from '../authorization/jwt-auth.guard.js';
import { RollupFilterDto } from './dto/rollup-filter.dto.js';
import { RollupsService } from './rollups.service.js';

@ApiTags('roll-up reports')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('reports')
export class ReportsController {
  constructor(private readonly rollups: RollupsService) {}

  @Get('org-units/:id/converts')
  @ApiOperation({
    summary: 'Read fast, current-stage daily summary totals for one RLS-scoped hierarchy unit',
  })
  @ApiOkResponse({
    description:
      'One count per convert at the unit and its hierarchy level; optional date/stage filters.',
  })
  getUnitRollup(
    @CurrentActor() actor: AuthenticatedActor,
    @Param('id') id: string,
    @Query() filter: RollupFilterDto,
  ) {
    return this.rollups.getUnitRollup(actor, id, filter);
  }
}
