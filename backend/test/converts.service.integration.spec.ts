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
      PII_LOOKUP_PEPPER: 'convert-test-lookup-pepper-which-is-at-least-thirty-two-bytes',
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

  it('shows above-parish registrations in the ageing Unassigned Pool and starts follow-up tasks on assignment', async () => {
    const existing = await testDatabase.pool.query<{ id: string }>(
      'SELECT id FROM converts LIMIT 1',
    );
    await testDatabase.pool.query(
      `UPDATE converts SET created_at = now() - interval '3 days 2 hours' WHERE id = $1`,
      [existing.rows[0].id],
    );

    const pool = await converts.listUnassigned(areaActor);
    expect(pool).toHaveLength(1);
    expect(pool[0]).toMatchObject({ id: existing.rows[0].id, unassignedAgeDays: 3 });

    const assigned = await converts.assignToParish(areaActor, existing.rows[0].id, {
      parishId: units.get('NG-PAR-A')!.id,
    });
    expect(assigned.parishId).toBe(units.get('NG-PAR-A')?.id);
    expect(assigned.assignedBy).toBe(areaActor.id);
    expect(await converts.listUnassigned(areaActor)).toEqual([]);

    const tasks = await testDatabase.pool.query<{
      task_type: string;
      parish_id: string;
      status: string;
    }>(
      `SELECT task_type::text, parish_id, status::text FROM follow_up_tasks
       WHERE convert_id = $1 ORDER BY task_type`,
      [existing.rows[0].id],
    );
    expect(tasks.rows).toEqual([
      { task_type: 'CALL_24H', parish_id: units.get('NG-PAR-A')?.id, status: 'PENDING' },
      { task_type: 'PRAYER_DAY_3', parish_id: units.get('NG-PAR-A')?.id, status: 'PENDING' },
      { task_type: 'VISIT_DAY_7', parish_id: units.get('NG-PAR-A')?.id, status: 'PENDING' },
    ]);
    await expect(
      converts.assignToParish(areaActor, existing.rows[0].id, {
        parishId: units.get('NG-PAR-B')!.id,
      }),
    ).rejects.toThrow(/already assigned/i);
  });

  it('assigns a parish registration immediately and starts parish follow-up without an Unassigned Pool delay', async () => {
    const created = await converts.create(parishActor, {
      fullName: 'Parish Convert',
      consent: { granted: true, version: '2026-11', method: 'VERBAL' },
    });
    expect(created.parishId).toBe(units.get('NG-PAR-B')?.id);
    expect(created.assignedBy).toBe(parishActor.id);
    const scheduled = await testDatabase.pool.query<{ count: string }>(
      `SELECT count(*) FROM follow_up_tasks WHERE convert_id = $1`,
      [created.id],
    );
    expect(scheduled.rows[0].count).toBe('3');
  });

  it('advances the fixed stage pipeline one step at a time and retains an append-only encrypted timeline', async () => {
    const parishConvert = await converts.create(parishActor, {
      fullName: 'Timeline Convert',
      consent: { granted: true, version: '2026-11', method: 'DIGITAL' },
    });
    expect(parishConvert.stage).toBe('NEW_CONVERT');

    const advanced = await converts.advanceStage(parishActor, parishConvert.id, {
      stage: 'BELIEVERS_CLASS',
      note: 'Attended first class.',
    });
    expect(advanced.stage).toBe('BELIEVERS_CLASS');
    await expect(
      converts.advanceStage(parishActor, parishConvert.id, { stage: 'BAPTISED' }),
    ).rejects.toThrow(/exactly one configured step/i);

    const activity = await converts.addActivity(parishActor, parishConvert.id, {
      note: 'Called and encouraged attendance.',
    });
    expect(activity).toMatchObject({
      eventType: 'NOTE',
      note: 'Called and encouraged attendance.',
    });
    const timeline = await converts.timeline(parishActor, parishConvert.id);
    expect(timeline.map((event) => event.eventType)).toEqual([
      'REGISTERED',
      'PARISH_ASSIGNED',
      'STAGE_ADVANCED',
      'NOTE',
    ]);
    expect(timeline[2]).toMatchObject({
      fromStage: 'NEW_CONVERT',
      toStage: 'BELIEVERS_CLASS',
      note: 'Attended first class.',
    });

    const storedNote = await testDatabase.pool.query<{ note_encrypted: Buffer }>(
      `SELECT note_encrypted FROM convert_timeline_events
       WHERE convert_id = $1 AND event_type = 'NOTE'`,
      [parishConvert.id],
    );
    expect(storedNote.rows[0].note_encrypted.toString('utf8')).not.toContain(
      'Called and encouraged',
    );
    await expect(
      testDatabase.pool.query(
        `UPDATE convert_timeline_events SET metadata = '{"tampered":true}'::jsonb WHERE id = $1`,
        [timeline[0].id],
      ),
    ).rejects.toThrow(/append-only/i);
  });

  it('detects visible phone duplicates and merges only the duplicate into a canonical convert', async () => {
    const primary = await converts.create(areaActor, {
      fullName: 'Primary Candidate',
      phone: '+2348030000111',
      consent: { granted: true, version: '2026-11', method: 'DIGITAL' },
    });
    const duplicate = await converts.create(areaActor, {
      fullName: 'Duplicate Candidate',
      phone: '+2348030000111',
      consent: { granted: true, version: '2026-11', method: 'DIGITAL' },
    });
    const candidates = await converts.detectDuplicates(areaActor, { phone: '+234 803 000 0111' });
    expect(candidates.map((candidate) => candidate.id)).toEqual([primary.id, duplicate.id]);

    const mergedTarget = await converts.merge(areaActor, primary.id, {
      duplicateConvertId: duplicate.id,
    });
    expect(mergedTarget.id).toBe(primary.id);
    const source = await converts.get(areaActor, duplicate.id);
    expect(source.mergedIntoId).toBe(primary.id);
    const unassigned = await converts.listUnassigned(areaActor);
    expect(unassigned.some((convert) => convert.id === duplicate.id)).toBe(false);

    const audit = await testDatabase.pool.query<{
      action: string;
      metadata: { mergedDuplicateConvertId: string };
    }>(
      `SELECT action, metadata FROM audit_log WHERE resource_id = $1 AND action = 'CONVERT_MERGED'`,
      [primary.id],
    );
    expect(audit.rows[0].metadata.mergedDuplicateConvertId).toBe(duplicate.id);
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
