import { Controller, Get } from '@nestjs/common';
import { ApiOkResponse, ApiOperation, ApiTags } from '@nestjs/swagger';
import { DatabaseHealthService } from './database-health.service.js';

@ApiTags('system')
@Controller()
export class HealthController {
  constructor(private readonly database: DatabaseHealthService) {}

  @Get('hello')
  @ApiOperation({ summary: 'Return the API welcome response' })
  @ApiOkResponse({ description: 'API is reachable.' })
  hello(): { message: string; service: string } {
    return {
      message: 'Go-Ye API is ready.',
      service: 'go-ye-api',
    };
  }

  @Get('health')
  @ApiOperation({ summary: 'Report API and database reachability' })
  @ApiOkResponse({ description: 'Health status for orchestration and development checks.' })
  async health(): Promise<{
    status: 'ok';
    database: 'connected' | 'not-configured' | 'unavailable';
  }> {
    return {
      status: 'ok',
      database: await this.database.check(),
    };
  }
}
