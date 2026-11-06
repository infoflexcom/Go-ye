import { Body, Controller, Get, Patch, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOkResponse, ApiOperation, ApiTags } from '@nestjs/swagger';
import type { AuthenticatedActor } from '../authorization/authorization.types.js';
import { CurrentActor } from '../authorization/current-actor.decorator.js';
import { JwtAuthGuard } from '../authorization/jwt-auth.guard.js';
import { RequireRoles } from '../authorization/roles.decorator.js';
import { RolesGuard } from '../authorization/roles.guard.js';
import { UpdatePhoneMaskingDto } from './dto/update-phone-masking.dto.js';
import { PrivacySettingsService } from './privacy-settings.service.js';

@ApiTags('privacy settings')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, RolesGuard)
@RequireRoles('GLOBAL_ADMIN')
@Controller('privacy/settings')
export class PrivacySettingsController {
  constructor(private readonly settings: PrivacySettingsService) {}

  @Get('phone-masking')
  @ApiOperation({ summary: 'Read the server-enforced above-Parish phone masking setting' })
  @ApiOkResponse({ description: 'The setting defaults to false and is read at request time.' })
  getPhoneMasking(@CurrentActor() actor: AuthenticatedActor) {
    return this.settings.getPhoneMasking(actor);
  }

  @Patch('phone-masking')
  @ApiOperation({ summary: 'Update phone masking without releasing a new client application' })
  updatePhoneMasking(
    @CurrentActor() actor: AuthenticatedActor,
    @Body() dto: UpdatePhoneMaskingDto,
  ) {
    return this.settings.updatePhoneMasking(actor, dto.maskPhoneNumbersAboveParish);
  }
}
