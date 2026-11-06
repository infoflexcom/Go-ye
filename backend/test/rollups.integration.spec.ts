import { ConfigService } from '@nestjs/config';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { AdminReportsService } from '../src/admin/admin-reports.service.js';
import { AuditService } from '../src/audit/audit.service.js';
import type { AuthenticatedActor } from '../src/authorization/authorization.types.js';
import { DatabaseService } from '../src/database/database.service.js';
import { FieldEncryptionService } from '../src/privacy/field-encryption.service.js';
import { PrivacySettingsService } from '../src/privacy/privacy-settings.service.js';
import { RollupsService } from '../src/reports/rollups.service.js';
import type { TestDatabase } from './support/embedded-postgres.js';
import { createTestDatabase } from './support/embedded-postgres.js';

const piiKey = Buffer.alloc(32, 12).toString('base64');
const auditSecret = 'rollup-test-audit-secret-which-is-at-least-thirty-two-bytes';

interface Unit {
  id: string;
  path: string;
}

describe('convert hierarchy roll-ups', () => {
  let testDatabase: TestDatabase;
  let database: DatabaseService;
  let rollups: RollupsService;
  let adminReports: AdminReportsService;
  let encryption: FieldEncryptionService;
  let privacySettings: PrivacySettingsService;
  let parishNewId: string;
  let countryActor: AuthenticatedActor;
  let globalActor: AuthenticatedActor;
  const units = new Map<string, Unit>();

  beforeAll(async () => {
    testDatabase = await createTestDatabase();
    const config = new ConfigService({
      DATABASE_URL: testDatabase.connectionString,
      PII_ENCRYPTION_KEY: piiKey,
      AUDIT_CHAIN_SECRET: auditSecret,
    });
    database = new DatabaseService(config);
    encryption = new FieldEncryptionService(config);
    rollups = new RollupsService(database);
    const audit = new AuditService();
    privacySettings = new PrivacySettingsService(database, audit, config);
    adminReports = new AdminReportsService(database, encryption, config, audit, privacySettings);

    async function unit(type: string, code: string, parentCode?: string): Promise<void> {
      const result = await testDatabase.pool.query<Unit>(
        `INSERT INTO org_units (type, name, code, parent_id)
         VALUES ($1::org_unit_type, $2, $3, $4) RETURNING id, path::text`,
        [type, code, code, parentCode ? units.get(parentCode)?.id : null],
      );
      units.set(code, result.rows[0]);
    }
    await unit('COUNTRY', 'NG');
    await unit('REGION', 'NG-REG', 'NG');
    await unit('PROVINCE', 'NG-PRO', 'NG-REG');
    await unit('ZONE', 'NG-ZON', 'NG-PRO');
    await unit('AREA', 'NG-ARE', 'NG-ZON');
    await unit('PARISH', 'NG-PAR-A', 'NG-ARE');
    await unit('PARISH', 'NG-PAR-B', 'NG-ARE');
    await unit('COUNTRY', 'GH');

    const countryUser = await testDatabase.pool.query<{ id: string }>(
      `INSERT INTO users (display_name, email_normalized, home_unit_id, status)
       VALUES ('Country reporting', 'country.reporting@rollup.test', $1, 'ACTIVE') RETURNING id`,
      [units.get('NG')?.id],
    );
    countryActor = {
      id: countryUser.rows[0].id,
      sessionId: '00000000-0000-0000-0000-000000000031',
      roles: ['COUNTRY_ADMIN'],
      homeUnitId: units.get('NG')?.id,
      homePath: units.get('NG')?.path,
      isGlobalAdmin: false,
    };
    const globalUser = await testDatabase.pool.query<{ id: string }>(
      `INSERT INTO users (display_name, email_normalized, status)
       VALUES ('Global reporting', 'global.reporting@rollup.test', 'ACTIVE') RETURNING id`,
    );
    globalActor = {
      id: globalUser.rows[0].id,
      sessionId: '00000000-0000-0000-0000-000000000032',
      roles: ['GLOBAL_ADMIN'],
      isGlobalAdmin: true,
    };

    async function convert(
      registrationCode: string,
      stage: string,
      parishCode?: string,
    ): Promise<string> {
      const result = await testDatabase.pool.query<{ id: string }>(
        `INSERT INTO converts (
          full_name_encrypted, registered_at_unit_id, registered_by, parish_id,
          consent_granted, consent_version, consent_method, consent_captured_by, stage
        ) VALUES ($1, $2, $3, $4, true, '2026-11', 'DIGITAL', $3, $5::convert_stage)
        RETURNING id`,
        [
          encryption.encrypt(`${registrationCode}-${stage}-${parishCode ?? 'unassigned'}`),
          units.get(registrationCode)?.id,
          countryUser.rows[0].id,
          parishCode ? units.get(parishCode)?.id : null,
          stage,
        ],
      );
      return result.rows[0].id;
    }

    parishNewId = await convert('NG-PAR-A', 'NEW_CONVERT', 'NG-PAR-A');
    await convert('NG-PAR-A', 'BAPTISED', 'NG-PAR-A');
    await convert('NG-ARE', 'NEW_CONVERT');
    await convert('NG', 'FULLY_PLANTED', 'NG-PAR-B');
    await convert('GH', 'NEW_CONVERT');
    const duplicate = await convert('NG-PAR-A', 'NEW_CONVERT', 'NG-PAR-A');
    await testDatabase.pool.query(
      `UPDATE converts SET merged_into_id = $1, merged_at = now(), merged_by = $2 WHERE id = $3`,
      [parishNewId, countryUser.rows[0].id, duplicate],
    );
  }, 30_000);

  afterAll(async () => {
    await database.onModuleDestroy();
    await testDatabase.close();
  });

  it('counts each active convert once at Parish and once at every ancestor without double-counting', async () => {
    const expected = new Map([
      ['NG', 4],
      ['NG-REG', 4],
      ['NG-PRO', 4],
      ['NG-ZON', 4],
      ['NG-ARE', 4],
      ['NG-PAR-A', 2],
      ['NG-PAR-B', 1],
    ]);
    for (const [code, total] of expected) {
      await expect(
        rollups.getUnitRollup(countryActor, units.get(code)!.id, {}),
      ).resolves.toMatchObject({
        total,
      });
    }
    await expect(
      rollups.getUnitRollup(countryActor, units.get('NG')!.id, { stage: 'NEW_CONVERT' }),
    ).resolves.toEqual({
      unitId: units.get('NG')!.id,
      total: 2,
      byStage: { NEW_CONVERT: 2 },
    });
  });

  it('returns correct Global Admin country, region, country-total, grand-total and drill-down report data', async () => {
    await expect(adminReports.listCountries(globalActor, {})).resolves.toEqual([
      { id: units.get('GH')!.id, code: 'GH', name: 'GH', total: 1 },
      { id: units.get('NG')!.id, code: 'NG', name: 'NG', total: 4 },
    ]);
    await expect(adminReports.listRegions(globalActor, units.get('NG')!.id, {})).resolves.toEqual([
      { id: units.get('NG-REG')!.id, code: 'NG-REG', name: 'NG-REG', total: 4 },
    ]);
    await expect(
      adminReports.countryTotal(globalActor, units.get('NG')!.id, { stage: 'NEW_CONVERT' }),
    ).resolves.toEqual({ countryId: units.get('NG')!.id, countryCode: 'NG', total: 2 });
    await expect(adminReports.grandTotal(globalActor, {})).resolves.toEqual({ total: 5 });
    const drillDown = await adminReports.drillDownCountry(globalActor, units.get('NG')!.id, {});
    expect(drillDown.total).toBe(4);
    expect(drillDown.items).toHaveLength(4);
    expect(typeof drillDown.items[0].registeredAtUnitId).toBe('string');
    expect(typeof drillDown.items[0].fullName).toBe('string');

    await expect(
      adminReports.grandTotal(globalActor, { startDate: '1900-01-01', endDate: '1900-01-01' }),
    ).resolves.toEqual({ total: 0 });
    const pagedNewConverts = await adminReports.drillDownCountry(globalActor, units.get('NG')!.id, {
      stage: 'NEW_CONVERT',
      offset: 1,
      limit: 1,
    });
    expect(pagedNewConverts).toMatchObject({ total: 2 });
    expect(pagedNewConverts.items).toHaveLength(1);
    await expect(adminReports.grandTotal(countryActor, {})).rejects.toThrow(
      'Global Admin access is required',
    );

    await testDatabase.pool.query('UPDATE converts SET phone_encrypted = $1 WHERE id = $2', [
      encryption.encrypt('+2348030000066'),
      parishNewId,
    ]);
    const unmaskedDetail = await adminReports.drillDownCountry(
      globalActor,
      units.get('NG')!.id,
      {},
    );
    expect(unmaskedDetail.items.find((item) => item.id === parishNewId)?.phone).toBe(
      '+2348030000066',
    );
    await privacySettings.updatePhoneMasking(globalActor, true);
    const maskedDetail = await adminReports.drillDownCountry(globalActor, units.get('NG')!.id, {});
    expect(maskedDetail.items.find((item) => item.id === parishNewId)?.phone).toBe('***0066');

    const auditEvents = await testDatabase.pool.query<{ count: string }>(
      `SELECT count(*)::text AS count
       FROM audit_log
       WHERE action = 'GLOBAL_ADMIN_CONVERT_DRILL_DOWN_READ'`,
    );
    expect(Number(auditEvents.rows[0].count)).toBe(4);
  });

  it('keeps country totals isolated while allowing Global Admin to read a second country', async () => {
    await expect(rollups.getUnitRollup(countryActor, units.get('GH')!.id, {})).rejects.toThrow(
      /not found/i,
    );
    await expect(
      rollups.getUnitRollup(globalActor, units.get('GH')!.id, {}),
    ).resolves.toMatchObject({
      total: 1,
      byStage: { NEW_CONVERT: 1 },
    });
  });
});
