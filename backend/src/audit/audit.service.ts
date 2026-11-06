import { Injectable } from '@nestjs/common';
import type { PoolClient } from 'pg';

export interface AuditEvent {
  actorUserId?: string;
  action: string;
  resourceType: string;
  resourceId?: string;
  scopeUnitId?: string;
  metadata?: Record<string, unknown>;
}

@Injectable()
export class AuditService {
  async append(client: PoolClient, event: AuditEvent): Promise<void> {
    await client.query(`SELECT goye_append_audit_event($1, $2, $3, $4, $5, $6::jsonb)`, [
      event.actorUserId ?? null,
      event.action,
      event.resourceType,
      event.resourceId ?? null,
      event.scopeUnitId ?? null,
      JSON.stringify(event.metadata ?? {}),
    ]);
  }
}
