import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AdminModule } from './admin/admin.module.js';
import { AuditModule } from './audit/audit.module.js';
import { AuthorizationModule } from './authorization/authorization.module.js';
import { AuthModule } from './auth/auth.module.js';
import { environmentValidationSchema } from './config/environment.validation.js';
import { DatabaseModule } from './database/database.module.js';
import { DirectoryModule } from './directory/directory.module.js';
import { HealthModule } from './health/health.module.js';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      validationSchema: environmentValidationSchema,
    }),
    DatabaseModule,
    AuditModule,
    AdminModule,
    AuthModule,
    DirectoryModule,
    AuthorizationModule,
    HealthModule,
  ],
})
export class AppModule {}
