import { Body, Controller, Get, Param, Post, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOkResponse, ApiOperation, ApiTags } from '@nestjs/swagger';
import type { AuthenticatedActor } from '../authorization/authorization.types.js';
import { CurrentActor } from '../authorization/current-actor.decorator.js';
import { JwtAuthGuard } from '../authorization/jwt-auth.guard.js';
import { RequireRoles } from '../authorization/roles.decorator.js';
import { RolesGuard } from '../authorization/roles.guard.js';
import { PrivacyRemovalRequestFilterDto } from './dto/privacy-removal-request-filter.dto.js';
import { ResolveConvertRemovalDto } from './dto/resolve-convert-removal.dto.js';
import { PrivacyRemovalService } from './privacy-removal.service.js';

@ApiTags('privacy removal requests')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, RolesGuard)
@RequireRoles('GLOBAL_ADMIN', 'PRIVACY_OFFICER')
@Controller('privacy/removal-requests')
export class PrivacyRemovalController {
  constructor(private readonly privacy: PrivacyRemovalService) {}

  @Get()
  @ApiOperation({ summary: 'List scoped pending or resolved convert removal requests' })
  list(@CurrentActor() actor: AuthenticatedActor, @Query() filter: PrivacyRemovalRequestFilterDto) {
    return this.privacy.listRequests(actor, filter);
  }

  @Post(':id/resolve')
  @ApiOperation({
    summary: 'Approve anonymisation or reject a removal request with an encrypted resolution note',
  })
  @ApiOkResponse({
    description:
      'Anonymisation replaces direct PII, cancels pending follow-up and removes the record from routine access and totals.',
  })
  resolve(
    @CurrentActor() actor: AuthenticatedActor,
    @Param('id') id: string,
    @Body() dto: ResolveConvertRemovalDto,
  ) {
    return this.privacy.resolve(actor, id, dto);
  }
}
