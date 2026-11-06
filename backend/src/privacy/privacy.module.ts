import { Global, Module } from '@nestjs/common';
import { AuditModule } from '../audit/audit.module.js';
import { AuthModule } from '../auth/auth.module.js';
import { AuthorizationModule } from '../authorization/authorization.module.js';
import { PrivacyRemovalController } from './privacy-removal.controller.js';
import { PrivacyRemovalService } from './privacy-removal.service.js';
import { PrivacySettingsController } from './privacy-settings.controller.js';
import { PrivacySettingsService } from './privacy-settings.service.js';
import { FieldEncryptionService } from './field-encryption.service.js';

@Global()
@Module({
  imports: [AuditModule, AuthModule, AuthorizationModule],
  controllers: [PrivacyRemovalController, PrivacySettingsController],
  providers: [FieldEncryptionService, PrivacyRemovalService, PrivacySettingsService],
  exports: [FieldEncryptionService, PrivacyRemovalService, PrivacySettingsService],
})
export class PrivacyModule {}
