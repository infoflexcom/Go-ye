import { Module } from '@nestjs/common';
import { AuditModule } from '../audit/audit.module.js';
import { AuthModule } from '../auth/auth.module.js';
import { AuthorizationModule } from '../authorization/authorization.module.js';
import { FcmPushGatewayService } from './fcm-push-gateway.service.js';
import { FollowUpCadenceController } from './follow-up-cadence.controller.js';
import { FollowUpCadenceService } from './follow-up-cadence.service.js';
import { FollowUpReminderDeliveryService } from './follow-up-reminder-delivery.service.js';
import { FollowUpReminderQueueService } from './follow-up-reminder-queue.service.js';
import { FollowUpSchedulerService } from './follow-up-scheduler.service.js';
import { FollowUpTasksController } from './follow-up-tasks.controller.js';
import { FollowUpTasksService } from './follow-up-tasks.service.js';

@Module({
  imports: [AuditModule, AuthModule, AuthorizationModule],
  controllers: [FollowUpCadenceController, FollowUpTasksController],
  providers: [
    FollowUpCadenceService,
    FollowUpReminderQueueService,
    FollowUpSchedulerService,
    FollowUpTasksService,
    FcmPushGatewayService,
    FollowUpReminderDeliveryService,
  ],
  exports: [
    FollowUpCadenceService,
    FollowUpReminderQueueService,
    FollowUpSchedulerService,
    FollowUpTasksService,
  ],
})
export class FollowUpModule {}
