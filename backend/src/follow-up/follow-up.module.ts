import { Module } from '@nestjs/common';
import { AuditModule } from '../audit/audit.module.js';
import { AuthModule } from '../auth/auth.module.js';
import { AuthorizationModule } from '../authorization/authorization.module.js';
import { FollowUpCadenceController } from './follow-up-cadence.controller.js';
import { FollowUpCadenceService } from './follow-up-cadence.service.js';
import { FollowUpReminderQueueService } from './follow-up-reminder-queue.service.js';
import { FollowUpSchedulerService } from './follow-up-scheduler.service.js';

@Module({
  imports: [AuditModule, AuthModule, AuthorizationModule],
  controllers: [FollowUpCadenceController],
  providers: [FollowUpCadenceService, FollowUpReminderQueueService, FollowUpSchedulerService],
  exports: [FollowUpCadenceService, FollowUpReminderQueueService, FollowUpSchedulerService],
})
export class FollowUpModule {}
