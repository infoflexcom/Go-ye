import { Controller, Get, Param, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOkResponse, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentActor } from '../authorization/current-actor.decorator.js';
import { JwtAuthGuard } from '../authorization/jwt-auth.guard.js';
import type { AuthenticatedActor } from '../authorization/authorization.types.js';
import { DirectoryService } from './directory.service.js';

@ApiTags('organisation directory')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('directory')
export class DirectoryController {
  constructor(private readonly directory: DirectoryService) {}

  @Get('org-units')
  @ApiOperation({ summary: 'List the authenticated actor home unit and descendants only' })
  @ApiOkResponse({ description: 'RLS-scoped organisation unit list.' })
  listOrgUnits(@CurrentActor() actor: AuthenticatedActor) {
    return this.directory.listOrgUnits(actor);
  }

  @Get('org-units/:id')
  @ApiOperation({ summary: 'Read one organisation unit within RLS scope' })
  getOrgUnit(@CurrentActor() actor: AuthenticatedActor, @Param('id') id: string) {
    return this.directory.getOrgUnit(actor, id);
  }

  @Get('users/:id')
  @ApiOperation({ summary: 'Read one user within RLS scope without contact details' })
  getUser(@CurrentActor() actor: AuthenticatedActor, @Param('id') id: string) {
    return this.directory.getUser(actor, id);
  }
}
