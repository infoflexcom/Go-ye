import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { AuthorizationModule } from '../authorization/authorization.module.js';
import { ReportsController } from './reports.controller.js';
import { RollupsService } from './rollups.service.js';

@Module({
  imports: [AuthModule, AuthorizationModule],
  controllers: [ReportsController],
  providers: [RollupsService],
  exports: [RollupsService],
})
export class ReportsModule {}
