import { Module } from '@nestjs/common';
import { AuditModule } from '../audit/audit.module.js';
import { AuthModule } from '../auth/auth.module.js';
import { AuthorizationModule } from '../authorization/authorization.module.js';
import { FollowUpCadenceController } from './follow-up-cadence.controller.js';
import { FollowUpCadenceService } from './follow-up-cadence.service.js';

@Module({
  imports: [AuditModule, AuthModule, AuthorizationModule],
  controllers: [FollowUpCadenceController],
  providers: [FollowUpCadenceService],
  exports: [FollowUpCadenceService],
})
export class FollowUpModule {}
