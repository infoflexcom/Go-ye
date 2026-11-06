import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Pool } from 'pg';

@Injectable()
export class DatabaseHealthService implements OnModuleDestroy {
  private readonly pool?: Pool;

  constructor(config: ConfigService) {
    const connectionString = config.get<string>('DATABASE_URL');
    if (connectionString) {
      this.pool = new Pool({ connectionString, max: 1 });
    }
  }

  async check(): Promise<'connected' | 'not-configured' | 'unavailable'> {
    if (!this.pool) {
      return 'not-configured';
    }

    try {
      await this.pool.query('SELECT 1');
      return 'connected';
    } catch {
      return 'unavailable';
    }
  }

  async onModuleDestroy(): Promise<void> {
    await this.pool?.end();
  }
}
