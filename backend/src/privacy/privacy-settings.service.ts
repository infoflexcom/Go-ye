import { ForbiddenException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { PoolClient } from 'pg';
import { AuditService } from '../audit/audit.service.js';
import type { AuthenticatedActor } from '../authorization/authorization.types.js';
import { DatabaseService } from '../database/database.service.js';

interface PhoneMaskingRow {
  mask_phone_numbers_above_parish: boolean;
}

@Injectable()
export class PrivacySettingsService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly config: ConfigService,
  ) {}

  async getPhoneMasking(
    actor: AuthenticatedActor,
  ): Promise<{ maskPhoneNumbersAboveParish: boolean }> {
    this.assertGlobalAdmin(actor);
    return this.withActor(actor, async (client) => ({
      maskPhoneNumbersAboveParish: await this.maskPhoneNumbersAboveParish(client, actor),
    }));
  }

  async updatePhoneMasking(
    actor: AuthenticatedActor,
    enabled: boolean,
  ): Promise<{ maskPhoneNumbersAboveParish: boolean }> {
    this.assertGlobalAdmin(actor);
    return this.withActor(actor, async (client) => {
      const settings = await client.query<PhoneMaskingRow>(
        `UPDATE tenant_settings
         SET mask_phone_numbers_above_parish = $1
         WHERE singleton
         RETURNING mask_phone_numbers_above_parish`,
        [enabled],
      );
      await this.audit.append(client, {
        actorUserId: actor.id,
        action: 'PHONE_MASKING_ABOVE_PARISH_UPDATED',
        resourceType: 'TENANT_SETTINGS',
        metadata: { maskPhoneNumbersAboveParish: settings.rows[0].mask_phone_numbers_above_parish },
      });
      return { maskPhoneNumbersAboveParish: settings.rows[0].mask_phone_numbers_above_parish };
    });
  }

  async maskPhoneNumbersAboveParish(
    client: PoolClient,
    actor: AuthenticatedActor,
  ): Promise<boolean> {
    if (!actor.isGlobalAdmin) {
      if (!actor.homeUnitId) {
        return false;
      }
      const homeUnit = await client.query<{ type: string }>(
        'SELECT type::text FROM org_units WHERE id = $1',
        [actor.homeUnitId],
      );
      if (homeUnit.rows[0]?.type === 'PARISH') {
        return false;
      }
    }
    const settings = await client.query<PhoneMaskingRow>(
      'SELECT mask_phone_numbers_above_parish FROM tenant_settings WHERE singleton',
    );
    return settings.rows[0]?.mask_phone_numbers_above_parish === true;
  }

  private async withActor<T>(
    actor: AuthenticatedActor,
    callback: (client: PoolClient) => Promise<T>,
  ): Promise<T> {
    return this.database.withActor(
      {
        userId: actor.id,
        homePath: actor.homePath,
        isGlobalAdmin: actor.isGlobalAdmin,
        auditSecret: this.auditSecret(),
      },
      callback,
    );
  }

  private assertGlobalAdmin(actor: AuthenticatedActor): void {
    if (!actor.isGlobalAdmin || !actor.roles.includes('GLOBAL_ADMIN')) {
      throw new ForbiddenException('Global Admin access is required.');
    }
  }

  private auditSecret(): string {
    const secret = this.config.get<string>('AUDIT_CHAIN_SECRET');
    if (!secret || secret.startsWith('replace-with-') || secret.length < 32) {
      throw new Error('AUDIT_CHAIN_SECRET must be configured for privacy settings.');
    }
    return secret;
  }
}

export function maskPhoneNumber(value: string): string {
  return value.length <= 4 ? '***' : `***${value.slice(-4)}`;
}
