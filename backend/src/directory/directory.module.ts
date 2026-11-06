import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { AuthorizationModule } from '../authorization/authorization.module.js';
import { DirectoryController } from './directory.controller.js';
import { DirectoryService } from './directory.service.js';

@Module({
  imports: [AuthModule, AuthorizationModule],
  controllers: [DirectoryController],
  providers: [DirectoryService],
})
export class DirectoryModule {}
