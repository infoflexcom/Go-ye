import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { AuthorizationModule } from '../authorization/authorization.module.js';
import { ConvertsController } from './converts.controller.js';
import { ConvertsService } from './converts.service.js';

@Module({
  imports: [AuthModule, AuthorizationModule],
  controllers: [ConvertsController],
  providers: [ConvertsService],
  exports: [ConvertsService],
})
export class ConvertsModule {}
