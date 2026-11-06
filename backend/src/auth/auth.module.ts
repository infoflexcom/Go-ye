import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AuditModule } from '../audit/audit.module.js';
import { AuthController } from './auth.controller.js';
import { AuthService } from './auth.service.js';
import { DisabledOtpDeliveryService } from './disabled-otp-delivery.service.js';
import { OTP_DELIVERY_SERVICE } from './auth.types.js';

@Module({
  imports: [JwtModule.register({}), AuditModule],
  controllers: [AuthController],
  providers: [
    AuthService,
    DisabledOtpDeliveryService,
    {
      provide: OTP_DELIVERY_SERVICE,
      useExisting: DisabledOtpDeliveryService,
    },
  ],
  exports: [AuthService],
})
export class AuthModule {}
