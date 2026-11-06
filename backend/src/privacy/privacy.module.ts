import { Global, Module } from '@nestjs/common';
import { AuditModule } from '../audit/audit.module.js';
import { AuthModule } from '../auth/auth.module.js';
import { AuthorizationModule } from '../authorization/authorization.module.js';
import { PrivacyRemovalController } from './privacy-removal.controller.js';
import { PrivacyRemovalService } from './privacy-removal.service.js';
import { FieldEncryptionService } from './field-encryption.service.js';

@Global()
@Module({
  imports: [AuditModule, AuthModule, AuthorizationModule],
  controllers: [PrivacyRemovalController],
  providers: [FieldEncryptionService, PrivacyRemovalService],
  exports: [FieldEncryptionService, PrivacyRemovalService],
})
export class PrivacyModule {}
