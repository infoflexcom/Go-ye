import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOkResponse, ApiOperation, ApiTags } from '@nestjs/swagger';
import type { AuthenticatedActor } from '../authorization/authorization.types.js';
import { CurrentActor } from '../authorization/current-actor.decorator.js';
import { JwtAuthGuard } from '../authorization/jwt-auth.guard.js';
import { CompleteFollowUpTaskDto } from './dto/complete-follow-up-task.dto.js';
import { RegisterPushTokenDto } from './dto/register-push-token.dto.js';
import { FollowUpTasksService } from './follow-up-tasks.service.js';

@ApiTags('follow-up')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('follow-up')
export class FollowUpTasksController {
  constructor(private readonly tasks: FollowUpTasksService) {}

  @Get('today')
  @ApiOperation({
    summary: 'List active scoped follow-up tasks due today in the configured church timezone',
  })
  @ApiOkResponse({ description: 'Pending follow-up tasks for the authenticated hierarchy scope.' })
  listToday(@CurrentActor() actor: AuthenticatedActor) {
    return this.tasks.listToday(actor);
  }

  @Post('tasks/:id/complete')
  @ApiOperation({
    summary: 'Complete one pending follow-up task with an outcome and optional encrypted note',
  })
  complete(
    @CurrentActor() actor: AuthenticatedActor,
    @Param('id') id: string,
    @Body() dto: CompleteFollowUpTaskDto,
  ) {
    return this.tasks.complete(actor, id, dto);
  }

  @Post('push-tokens')
  @ApiOperation({
    summary: 'Register the active Android session FCM token for follow-up reminders',
  })
  registerPushToken(@CurrentActor() actor: AuthenticatedActor, @Body() dto: RegisterPushTokenDto) {
    return this.tasks.registerPushToken(actor, dto);
  }
}
