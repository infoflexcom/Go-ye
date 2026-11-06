import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Pool, type PoolClient, type QueryResultRow } from 'pg';

export interface DatabaseActor {
  userId?: string;
  homePath?: string;
  isGlobalAdmin?: boolean;
  isSystem?: boolean;
  auditSecret?: string;
}

@Injectable()
export class DatabaseService implements OnModuleDestroy {
  private readonly pool?: Pool;

  constructor(config: ConfigService) {
    const connectionString = config.get<string>('DATABASE_URL');
    if (connectionString) {
      this.pool = new Pool({ connectionString });
    }
  }

  isConfigured(): boolean {
    return this.pool !== undefined;
  }

  async withActor<T>(
    actor: DatabaseActor,
    callback: (client: PoolClient) => Promise<T>,
  ): Promise<T> {
    if (!this.pool) {
      throw new Error('DATABASE_URL is required for database-backed operations');
    }
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(
        `SELECT
          set_config('goye.user_id', $1, true),
          set_config('goye.home_path', $2, true),
          set_config('goye.is_global_admin', $3, true),
          set_config('goye.is_system', $4, true),
          set_config('goye.audit_secret', $5, true)`,
        [
          actor.userId ?? '',
          actor.homePath ?? '',
          String(actor.isGlobalAdmin === true),
          String(actor.isSystem === true),
          actor.auditSecret ?? '',
        ],
      );
      const result = await callback(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async query<T extends QueryResultRow>(
    sql: string,
    params: readonly unknown[] = [],
  ): Promise<readonly T[]> {
    if (!this.pool) {
      throw new Error('DATABASE_URL is required for database-backed operations');
    }
    return (await this.pool.query<T>(sql, [...params])).rows;
  }

  async onModuleDestroy(): Promise<void> {
    await this.pool?.end();
  }
}
