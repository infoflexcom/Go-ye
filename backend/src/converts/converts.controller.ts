import { Body, Controller, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiCreatedResponse,
  ApiOkResponse,
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import type { AuthenticatedActor } from '../authorization/authorization.types.js';
import { CurrentActor } from '../authorization/current-actor.decorator.js';
import { JwtAuthGuard } from '../authorization/jwt-auth.guard.js';
import { AssignConvertDto } from './dto/assign-convert.dto.js';
import { CreateConvertDto } from './dto/create-convert.dto.js';
import { UpdateConvertDto } from './dto/update-convert.dto.js';
import { ConvertsService } from './converts.service.js';

@ApiTags('converts')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('converts')
export class ConvertsController {
  constructor(private readonly converts: ConvertsService) {}

  @Post()
  @ApiOperation({ summary: 'Register a convert with mandatory affirmative consent' })
  @ApiCreatedResponse({
    description:
      'Encrypted contact data is stored; consent actor and server timestamp are recorded.',
  })
  create(@CurrentActor() actor: AuthenticatedActor, @Body() dto: CreateConvertDto) {
    return this.converts.create(actor, dto);
  }

  @Get('unassigned')
  @ApiOperation({
    summary:
      'List visible above-parish registrations awaiting parish assignment and their live age in days',
  })
  listUnassigned(@CurrentActor() actor: AuthenticatedActor) {
    return this.converts.listUnassigned(actor);
  }

  @Post(':id/assign-parish')
  @ApiOperation({
    summary:
      'Assign an unassigned convert to a descendant parish and start the default follow-up plan',
  })
  assignToParish(
    @CurrentActor() actor: AuthenticatedActor,
    @Param('id') id: string,
    @Body() dto: AssignConvertDto,
  ) {
    return this.converts.assignToParish(actor, id, dto);
  }

  @Get(':id')
  @ApiOperation({ summary: 'Read a single convert within the authenticated hierarchy scope' })
  @ApiOkResponse({ description: 'A scoped convert; outside-scope IDs return 404.' })
  get(@CurrentActor() actor: AuthenticatedActor, @Param('id') id: string) {
    return this.converts.get(actor, id);
  }

  @Patch(':id')
  @ApiOperation({ summary: 'Update editable encrypted convert contact fields' })
  update(
    @CurrentActor() actor: AuthenticatedActor,
    @Param('id') id: string,
    @Body() dto: UpdateConvertDto,
  ) {
    return this.converts.update(actor, id, dto);
  }
}
