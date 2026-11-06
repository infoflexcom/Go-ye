import { ConfigService } from '@nestjs/config';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { AuditService } from '../src/audit/audit.service.js';
import type { AuthenticatedActor } from '../src/authorization/authorization.types.js';
import { ConvertsService } from '../src/converts/converts.service.js';
import { DatabaseService } from '../src/database/database.service.js';
import { FieldEncryptionService } from '../src/privacy/field-encryption.service.js';
import type { TestDatabase } from './support/embedded-postgres.js';
import { createTestDatabase } from './support/embedded-postgres.js';

const auditSecret = 'convert-test-audit-secret-which-is-at-least-thirty-two-bytes';
const piiKey = Buffer.alloc(32, 7).toString('base64');

interface Unit {
  id: string;
  path: string;
}

interface TestActor extends AuthenticatedActor {
  homeUnitId: string;
  homePath: string;
}

describe('ConvertsService', () => {
  let testDatabase: TestDatabase;
  let database: DatabaseService;
  let converts: ConvertsService;
  let areaActor: TestActor;
  let parishActor: TestActor;
  const units = new Map<string, Unit>();

  beforeAll(async () => {
    testDatabase = await createTestDatabase();
    const config = new ConfigService({
      DATABASE_URL: testDatabase.connectionString,
      AUDIT_CHAIN_SECRET: auditSecret,
      PII_ENCRYPTION_KEY: piiKey,
    });
    database = new DatabaseService(config);
    converts = new ConvertsService(
      database,
      new FieldEncryptionService(config),
      new AuditService(),
      config,
    );

    async function unit(type: string, code: string, parentCode?: string): Promise<void> {
      const row = await testDatabase.pool.query<Unit>(
        `INSERT INTO org_units (type, name, code, parent_id)
         VALUES ($1::org_unit_type, $2, $3, $4)
         RETURNING id, path::text`,
        [type, code, code, parentCode ? units.get(parentCode)?.id : null],
      );
      units.set(code, row.rows[0]);
    }
    await unit('COUNTRY', 'NG');
    await unit('REGION', 'NG-REG', 'NG');
    await unit('PROVINCE', 'NG-PRO', 'NG-REG');
    await unit('ZONE', 'NG-ZON', 'NG-PRO');
    await unit('AREA', 'NG-ARE', 'NG-ZON');
    await unit('PARISH', 'NG-PAR-A', 'NG-ARE');
    await unit('PARISH', 'NG-PAR-B', 'NG-ARE');

    async function actor(
      name: string,
      homeCode: string,
      role: string,
      sessionId: string,
    ): Promise<TestActor> {
      const user = await testDatabase.pool.query<{ id: string }>(
        `INSERT INTO users (display_name, email_normalized, home_unit_id, status)
         VALUES ($1, $2, $3, 'ACTIVE') RETURNING id`,
        [name, `${name.toLowerCase().replaceAll(' ', '.')}@convert.test`, units.get(homeCode)?.id],
      );
      await testDatabase.pool.query(
        `INSERT INTO user_roles (user_id, role_id, assigned_by)
         SELECT $1, id, $1 FROM roles WHERE key = $2`,
        [user.rows[0].id, role],
      );
      const home = units.get(homeCode)!;
      return {
        id: user.rows[0].id,
        sessionId,
        roles: [role],
        homeUnitId: home.id,
        homePath: home.path,
        isGlobalAdmin: false,
      };
    }

    areaActor = await actor(
      'Area Soul Winner',
      'NG-ARE',
      'AREA_LEADER',
      '00000000-0000-0000-0000-000000000021',
    );
    parishActor = await actor(
      'Parish Beta Worker',
      'NG-PAR-B',
      'SOUL_WINNER',
      '00000000-0000-0000-0000-000000000022',
    );
  }, 30_000);

  afterAll(async () => {
    await database.onModuleDestroy();
    await testDatabase.close();
  });

  it('registers at an above-parish home unit only with immutable consent and encrypted contact fields', async () => {
    const created = await converts.create(areaActor, {
      fullName: 'Ada Example',
      phone: '+234 803 000 0001',
      address: '10 Example Street, Lagos',
      consent: { granted: true, version: '2026-11', method: 'DIGITAL' },
    });

    expect(created).toMatchObject({
      fullName: 'Ada Example',
      phone: '+2348030000001',
      address: '10 Example Street, Lagos',
      registeredAtUnitId: units.get('NG-ARE')?.id,
      registeredBy: areaActor.id,
      consent: { version: '2026-11', method: 'DIGITAL', capturedBy: areaActor.id },
    });
    expect(created.parishId).toBeUndefined();

    const stored = await testDatabase.pool.query<{
      full_name_encrypted: Buffer;
      phone_encrypted: Buffer;
      address_encrypted: Buffer;
      consent_captured_by: string;
    }>(
      `SELECT full_name_encrypted, phone_encrypted, address_encrypted, consent_captured_by
       FROM converts WHERE id = $1`,
      [created.id],
    );
    expect(stored.rows[0].full_name_encrypted.toString('utf8')).not.toContain('Ada Example');
    expect(stored.rows[0].phone_encrypted.toString('utf8')).not.toContain('+2348030000001');
    expect(stored.rows[0].address_encrypted.toString('utf8')).not.toContain('Example Street');
    expect(stored.rows[0].consent_captured_by).toBe(areaActor.id);

    await expect(
      testDatabase.pool.query(`UPDATE converts SET consent_version = 'altered' WHERE id = $1`, [
        created.id,
      ]),
    ).rejects.toThrow(/captured consent is immutable/i);

    const audited = await testDatabase.pool.query<{
      action: string;
      metadata: Record<string, unknown>;
    }>(`SELECT action, metadata FROM audit_log WHERE resource_id = $1`, [created.id]);
    expect(audited.rows).toEqual([
      {
        action: 'CONVERT_REGISTERED_WITH_CONSENT',
        metadata: {
          consentMethod: 'DIGITAL',
          consentVersion: '2026-11',
          registrationUnitId: units.get('NG-ARE')?.id,
        },
      },
    ]);
  });

  it('does not permit consent bypass, cross-unit registration, or guessed scoped reads', async () => {
    await expect(
      converts.create(areaActor, {
        fullName: 'No Consent',
        consent: { granted: false, version: '2026-11', method: 'VERBAL' },
      }),
    ).rejects.toThrow(/affirmatively granted/i);
    await expect(
      converts.create(areaActor, {
        fullName: 'Wrong Unit',
        registeredAtUnitId: units.get('NG-PAR-A')?.id,
        consent: { granted: true, version: '2026-11', method: 'VERBAL' },
      }),
    ).rejects.toThrow(/home unit/i);

    const existing = await testDatabase.pool.query<{ id: string }>(
      'SELECT id FROM converts LIMIT 1',
    );
    await expect(converts.get(parishActor, existing.rows[0].id)).rejects.toThrow(/not found/i);
  });

  it('updates editable encrypted fields without changing registration or consent provenance', async () => {
    const existing = await testDatabase.pool.query<{ id: string }>(
      'SELECT id FROM converts LIMIT 1',
    );
    const updated = await converts.update(areaActor, existing.rows[0].id, {
      phone: '+234 803 000 0099',
      address: '11 Updated Street, Lagos',
    });
    expect(updated.phone).toBe('+2348030000099');
    expect(updated.address).toBe('11 Updated Street, Lagos');
    expect(updated.registeredAtUnitId).toBe(units.get('NG-ARE')?.id);
    expect(updated.consent.capturedBy).toBe(areaActor.id);
  });
});
