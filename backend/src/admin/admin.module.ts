import { Module } from '@nestjs/common';
import { AuditModule } from '../audit/audit.module.js';
import { AuthModule } from '../auth/auth.module.js';
import { AuthorizationModule } from '../authorization/authorization.module.js';
import { AdminReportsController } from './admin-reports.controller.js';
import { AdminReportsService } from './admin-reports.service.js';
import { AdminController } from './admin.controller.js';
import { AdminService } from './admin.service.js';

@Module({
  imports: [AuditModule, AuthModule, AuthorizationModule],
  controllers: [AdminController, AdminReportsController],
  providers: [AdminService, AdminReportsService],
  exports: [AdminService],
})
export class AdminModule {}
