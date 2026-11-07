import { Body, Controller, Get, Param, Patch, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOkResponse, ApiOperation, ApiTags } from '@nestjs/swagger';
import type { AuthenticatedActor } from '../authorization/authorization.types.js';
import { CurrentActor } from '../authorization/current-actor.decorator.js';
import { JwtAuthGuard } from '../authorization/jwt-auth.guard.js';
import { RequireRoles } from '../authorization/roles.decorator.js';
import { RolesGuard } from '../authorization/roles.guard.js';
import { UpdateFollowUpCadenceStepDto } from './dto/update-follow-up-cadence-step.dto.js';
import { FollowUpCadenceService } from './follow-up-cadence.service.js';

@ApiTags('follow-up cadence')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, RolesGuard)
@RequireRoles('GLOBAL_ADMIN')
@Controller('follow-up/cadence')
export class FollowUpCadenceController {
  constructor(private readonly cadence: FollowUpCadenceService) {}

  @Get()
  @ApiOperation({ summary: 'Read the server-enforced follow-up cadence configuration' })
  @ApiOkResponse({ description: 'Ordered active/inactive cadence definitions.' })
  list(@CurrentActor() actor: AuthenticatedActor) {
    return this.cadence.list(actor);
  }

  @Patch(':code')
  @ApiOperation({
    summary: 'Update a cadence delay or activation without releasing a new client application',
  })
  update(
    @CurrentActor() actor: AuthenticatedActor,
    @Param('code') code: string,
    @Body() dto: UpdateFollowUpCadenceStepDto,
  ) {
    return this.cadence.update(actor, code, dto);
  }
}
