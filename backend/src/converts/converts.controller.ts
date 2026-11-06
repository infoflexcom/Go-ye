import { Body, Controller, Get, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
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
import { PrivacyRemovalService } from '../privacy/privacy-removal.service.js';
import { RequestConvertRemovalDto } from '../privacy/dto/request-convert-removal.dto.js';
import { AddConvertActivityDto } from './dto/add-convert-activity.dto.js';
import { AdvanceConvertStageDto } from './dto/advance-convert-stage.dto.js';
import { AssignConvertDto } from './dto/assign-convert.dto.js';
import { DetectDuplicateDto } from './dto/detect-duplicate.dto.js';
import { MergeConvertDto } from './dto/merge-convert.dto.js';
import { CreateConvertDto } from './dto/create-convert.dto.js';
import { UpdateConvertDto } from './dto/update-convert.dto.js';
import { ConvertsService } from './converts.service.js';

@ApiTags('converts')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('converts')
export class ConvertsController {
  constructor(
    private readonly converts: ConvertsService,
    private readonly privacy: PrivacyRemovalService,
  ) {}

  @Post()
  @ApiOperation({ summary: 'Register a convert with mandatory affirmative consent' })
  @ApiCreatedResponse({
    description:
      'Encrypted contact data is stored; consent actor and server timestamp are recorded.',
  })
  create(@CurrentActor() actor: AuthenticatedActor, @Body() dto: CreateConvertDto) {
    return this.converts.create(actor, dto);
  }

  @Get(':id/timeline')
  @ApiOperation({ summary: 'Read the append-only scoped convert activity timeline' })
  timeline(@CurrentActor() actor: AuthenticatedActor, @Param('id') id: string) {
    return this.converts.timeline(actor, id);
  }

  @Post(':id/activities')
  @ApiOperation({ summary: 'Append an encrypted activity note to a convert timeline' })
  addActivity(
    @CurrentActor() actor: AuthenticatedActor,
    @Param('id') id: string,
    @Body() dto: AddConvertActivityDto,
  ) {
    return this.converts.addActivity(actor, id, dto);
  }

  @Post(':id/stage')
  @ApiOperation({ summary: 'Advance one configured stage after parish assignment' })
  advanceStage(
    @CurrentActor() actor: AuthenticatedActor,
    @Param('id') id: string,
    @Body() dto: AdvanceConvertStageDto,
  ) {
    return this.converts.advanceStage(actor, id, dto);
  }

  @Get('duplicates')
  @ApiOperation({
    summary: 'Find visible active duplicate candidates by privacy-preserving phone lookup',
  })
  detectDuplicates(@CurrentActor() actor: AuthenticatedActor, @Query() dto: DetectDuplicateDto) {
    return this.converts.detectDuplicates(actor, dto);
  }

  @Post(':id/merge')
  @ApiOperation({
    summary: 'Merge one duplicate into the canonical convert without double-counting',
  })
  merge(
    @CurrentActor() actor: AuthenticatedActor,
    @Param('id') id: string,
    @Body() dto: MergeConvertDto,
  ) {
    return this.converts.merge(actor, id, dto);
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

  @Post(':id/removal-requests')
  @ApiOperation({
    summary: 'Request privacy removal; the convert is immediately hidden from routine access',
  })
  requestRemoval(
    @CurrentActor() actor: AuthenticatedActor,
    @Param('id') id: string,
    @Body() dto: RequestConvertRemovalDto,
  ) {
    return this.privacy.requestRemoval(actor, id, dto);
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
