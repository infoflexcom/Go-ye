import { ConfigService } from '@nestjs/config';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { AuditService } from '../src/audit/audit.service.js';
import type { AuthenticatedActor } from '../src/authorization/authorization.types.js';
import { ConvertsService } from '../src/converts/converts.service.js';
import { DatabaseService } from '../src/database/database.service.js';
import { FollowUpCadenceService } from '../src/follow-up/follow-up-cadence.service.js';
import { FollowUpTasksService } from '../src/follow-up/follow-up-tasks.service.js';
import { FieldEncryptionService } from '../src/privacy/field-encryption.service.js';
import { PrivacyRemovalService } from '../src/privacy/privacy-removal.service.js';
import { PrivacySettingsService } from '../src/privacy/privacy-settings.service.js';
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
  let privacy: PrivacyRemovalService;
  let privacySettings: PrivacySettingsService;
  let cadence: FollowUpCadenceService;
  let followUpTasks: FollowUpTasksService;
  let areaActor: TestActor;
  let parishActor: TestActor;
  let privacyActor: TestActor;
  let globalActor: AuthenticatedActor;
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
    const encryption = new FieldEncryptionService(config);
    const audit = new AuditService();
    privacySettings = new PrivacySettingsService(database, audit, config);
    cadence = new FollowUpCadenceService(database, audit, config);
    followUpTasks = new FollowUpTasksService(database, encryption, privacySettings, audit, config);
    converts = new ConvertsService(database, encryption, audit, config, privacySettings);
    privacy = new PrivacyRemovalService(database, encryption, audit, config);

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
    privacyActor = await actor(
      'Area Privacy Officer',
      'NG-ARE',
      'PRIVACY_OFFICER',
      '00000000-0000-0000-0000-000000000023',
    );
    const globalUser = await testDatabase.pool.query<{ id: string }>(
      `INSERT INTO users (display_name, email_normalized, status)
       VALUES ('Global Privacy Admin', 'global.privacy.admin@convert.test', 'ACTIVE') RETURNING id`,
    );
    await testDatabase.pool.query(
      `INSERT INTO user_roles (user_id, role_id, assigned_by)
       SELECT $1, id, $1 FROM roles WHERE key = 'GLOBAL_ADMIN'`,
      [globalUser.rows[0].id],
    );
    globalActor = {
      id: globalUser.rows[0].id,
      sessionId: '00000000-0000-0000-0000-000000000024',
      roles: ['GLOBAL_ADMIN'],
      isGlobalAdmin: true,
    };
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
      {
        task_type: 'WEEKLY_CHECK_IN',
        parish_id: units.get('NG-PAR-A')?.id,
        status: 'PENDING',
      },
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
    expect(scheduled.rows[0].count).toBe('4');
  });

  it('uses the Global Admin cadence configuration when parish follow-up begins', async () => {
    await expect(cadence.list(areaActor)).rejects.toThrow(/Global Admin/i);

    const defaults = await cadence.list(globalActor);
    expect(defaults.map((step) => [step.code, step.dueOffsetHours, step.recurrenceDays])).toEqual([
      ['CALL_24H', 24, undefined],
      ['PRAYER_DAY_3', 72, undefined],
      ['VISIT_DAY_7', 168, undefined],
      ['WEEKLY_CHECK_IN', 336, 7],
    ]);

    await expect(cadence.update(globalActor, 'CALL_24H', { recurrenceDays: 7 })).rejects.toThrow(
      /Only weekly check-ins/i,
    );
    await expect(cadence.update(areaActor, 'CALL_24H', { dueOffsetHours: 48 })).rejects.toThrow(
      /Global Admin/i,
    );

    await expect(
      cadence.update(globalActor, 'CALL_24H', { dueOffsetHours: 48 }),
    ).resolves.toMatchObject({ code: 'CALL_24H', dueOffsetHours: 48, isActive: true });

    const created = await converts.create(parishActor, {
      fullName: 'Configured Cadence Convert',
      consent: { granted: true, version: '2026-11', method: 'DIGITAL' },
    });
    const scheduled = await testDatabase.pool.query<{
      task_type: string;
      occurrence_number: number;
      due_offset_seconds: string;
    }>(
      `SELECT task_type::text, occurrence_number,
              extract(epoch FROM task.due_at - convert.assigned_at)::text AS due_offset_seconds
       FROM follow_up_tasks task
       JOIN converts convert ON convert.id = task.convert_id
       WHERE task.convert_id = $1
       ORDER BY task.task_type`,
      [created.id],
    );
    expect(scheduled.rows).toEqual([
      { task_type: 'CALL_24H', occurrence_number: 1, due_offset_seconds: '172800.000000' },
      { task_type: 'PRAYER_DAY_3', occurrence_number: 1, due_offset_seconds: '259200.000000' },
      { task_type: 'VISIT_DAY_7', occurrence_number: 1, due_offset_seconds: '604800.000000' },
      {
        task_type: 'WEEKLY_CHECK_IN',
        occurrence_number: 1,
        due_offset_seconds: '1209600.000000',
      },
    ]);

    const audited = await testDatabase.pool.query<{
      action: string;
      metadata: Record<string, unknown>;
    }>(`SELECT action, metadata FROM audit_log WHERE resource_type = 'FOLLOW_UP_CADENCE_STEP'`);
    expect(audited.rows).toEqual([
      {
        action: 'FOLLOW_UP_CADENCE_UPDATED',
        metadata: {
          code: 'CALL_24H',
          dueOffsetHours: 48,
          recurrenceDays: null,
          isActive: true,
        },
      },
    ]);

    await expect(
      cadence.update(globalActor, 'WEEKLY_CHECK_IN', { isActive: false }),
    ).resolves.toMatchObject({
      code: 'WEEKLY_CHECK_IN',
      isActive: false,
    });
    const withoutWeeklyCheckIn = await converts.create(parishActor, {
      fullName: 'No Weekly Check-in Convert',
      consent: { granted: true, version: '2026-11', method: 'DIGITAL' },
    });
    const weeklyTask = await testDatabase.pool.query<{ count: string }>(
      `SELECT count(*)::text AS count FROM follow_up_tasks
       WHERE convert_id = $1 AND task_type = 'WEEKLY_CHECK_IN'`,
      [withoutWeeklyCheckIn.id],
    );
    expect(weeklyTask.rows[0].count).toBe('0');
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

  it('audits an above-parish detail read but not an equivalent Parish read', async () => {
    const convert = await converts.create(parishActor, {
      fullName: 'Read Audit Convert',
      consent: { granted: true, version: '2026-11', method: 'VERBAL' },
    });
    await converts.get(areaActor, convert.id);
    await converts.get(parishActor, convert.id);

    const reads = await testDatabase.pool.query<{ count: string }>(
      `SELECT count(*)::text AS count
       FROM audit_log
       WHERE action = 'CONVERT_READ_ABOVE_PARISH' AND resource_id = $1`,
      [convert.id],
    );
    expect(reads.rows[0].count).toBe('1');
  });

  it('quarantines a removal request, permits only the Privacy Officer workflow, then erases PII by anonymisation', async () => {
    const convert = await converts.create(parishActor, {
      fullName: 'Removal Request Convert',
      phone: '+234 803 000 0033',
      address: '33 Removal Street, Lagos',
      consent: { granted: true, version: '2026-11', method: 'DIGITAL' },
    });
    const beforeRemoval = await testDatabase.pool.query<{ total: string }>(
      `SELECT COALESCE(sum(total_count), 0)::text AS total
       FROM convert_rollup_daily WHERE org_unit_id = $1`,
      [units.get('NG-PAR-B')!.id],
    );

    const request = await privacy.requestRemoval(parishActor, convert.id, {
      reason: 'The person withdrew consent.',
    });
    expect(request.status).toBe('PENDING');
    await expect(converts.get(areaActor, convert.id)).rejects.toThrow(/not found/i);
    await expect(converts.get(globalActor, convert.id)).rejects.toThrow(/not found/i);
    const afterRequest = await testDatabase.pool.query<{ total: string }>(
      `SELECT COALESCE(sum(total_count), 0)::text AS total
       FROM convert_rollup_daily WHERE org_unit_id = $1`,
      [units.get('NG-PAR-B')!.id],
    );
    expect(Number(afterRequest.rows[0].total)).toBe(Number(beforeRemoval.rows[0].total) - 1);

    await expect(
      privacy.resolve(areaActor, request.requestId, { outcome: 'ANONYMISE' }),
    ).rejects.toThrow(/Privacy Officer/i);
    const pendingRequest = [
      expect.objectContaining({
        id: request.requestId,
        convertId: convert.id,
        reason: 'The person withdrew consent.',
        status: 'PENDING',
      }),
    ];
    await expect(privacy.listRequests(privacyActor, { status: 'PENDING' })).resolves.toEqual(
      pendingRequest,
    );
    await expect(privacy.listRequests(globalActor, { status: 'PENDING' })).resolves.toEqual(
      pendingRequest,
    );

    await expect(
      privacy.resolve(privacyActor, request.requestId, {
        outcome: 'ANONYMISE',
        note: 'Identity checked and lawful request approved.',
      }),
    ).resolves.toEqual({ convertId: convert.id, status: 'ANONYMISED' });
    const stored = await testDatabase.pool.query<{
      privacy_status: string;
      phone_encrypted: Buffer | null;
      address_encrypted: Buffer | null;
      full_name_encrypted: Buffer;
    }>(
      `SELECT privacy_status::text, phone_encrypted, address_encrypted, full_name_encrypted
       FROM converts WHERE id = $1`,
      [convert.id],
    );
    expect(stored.rows[0].privacy_status).toBe('ANONYMISED');
    expect(stored.rows[0].phone_encrypted).toBeNull();
    expect(stored.rows[0].address_encrypted).toBeNull();
    expect(stored.rows[0].full_name_encrypted.toString('utf8')).not.toContain(
      'Removal Request Convert',
    );
    const pendingTasks = await testDatabase.pool.query<{ count: string }>(
      `SELECT count(*)::text AS count FROM follow_up_tasks
       WHERE convert_id = $1 AND status = 'PENDING'`,
      [convert.id],
    );
    expect(pendingTasks.rows[0].count).toBe('0');
    await expect(converts.get(parishActor, convert.id)).rejects.toThrow(/not found/i);
    await expect(privacy.listRequests(privacyActor, { status: 'ANONYMISED' })).resolves.toEqual([
      expect.objectContaining({
        id: request.requestId,
        status: 'ANONYMISED',
        resolutionNote: 'Identity checked and lawful request approved.',
      }),
    ]);

    const privacyAudit = await testDatabase.pool.query<{ action: string }>(
      `SELECT action FROM audit_log
       WHERE resource_id = $1
       ORDER BY occurred_at ASC, id ASC`,
      [request.requestId],
    );
    expect(privacyAudit.rows.map((row) => row.action).sort()).toEqual([
      'CONVERT_REMOVAL_ANONYMISED',
      'CONVERT_REMOVAL_REQUESTED',
    ]);
  });

  it('restores a rejected request to routine access and its prior roll-up contribution', async () => {
    const convert = await converts.create(parishActor, {
      fullName: 'Rejected Removal Convert',
      consent: { granted: true, version: '2026-11', method: 'VERBAL' },
    });
    const beforeRequest = await testDatabase.pool.query<{ total: string }>(
      `SELECT COALESCE(sum(total_count), 0)::text AS total
       FROM convert_rollup_daily WHERE org_unit_id = $1`,
      [units.get('NG-PAR-B')!.id],
    );
    const request = await privacy.requestRemoval(parishActor, convert.id, {});
    const duringRequest = await testDatabase.pool.query<{ total: string }>(
      `SELECT COALESCE(sum(total_count), 0)::text AS total
       FROM convert_rollup_daily WHERE org_unit_id = $1`,
      [units.get('NG-PAR-B')!.id],
    );
    expect(Number(duringRequest.rows[0].total)).toBe(Number(beforeRequest.rows[0].total) - 1);

    await expect(
      privacy.resolve(privacyActor, request.requestId, {
        outcome: 'REJECT',
        note: 'Identity not verified.',
      }),
    ).resolves.toEqual({ convertId: convert.id, status: 'REJECTED' });
    await expect(converts.get(parishActor, convert.id)).resolves.toMatchObject({ id: convert.id });
    const afterRejection = await testDatabase.pool.query<{ total: string }>(
      `SELECT COALESCE(sum(total_count), 0)::text AS total
       FROM convert_rollup_daily WHERE org_unit_id = $1`,
      [units.get('NG-PAR-B')!.id],
    );
    expect(afterRejection.rows[0].total).toBe(beforeRequest.rows[0].total);
  });

  it('lists only RLS-visible active converts with bounded pagination', async () => {
    const visible = await converts.create(parishActor, {
      fullName: 'Listed Parish Convert',
      consent: { granted: true, version: '2026-11', method: 'DIGITAL' },
    });
    const page = await converts.list(parishActor, { offset: 0, limit: 100 });

    expect(page.total).toBeGreaterThanOrEqual(1);
    expect(page.items.length).toBeGreaterThanOrEqual(1);
    expect(page.items.some((item) => item.id === visible.id)).toBe(true);
    const audit = await testDatabase.pool.query<{ action: string }>(
      `SELECT action FROM audit_log
       WHERE action = 'CONVERT_LIST_READ_ABOVE_PARISH' AND actor_user_id = $1`,
      [parishActor.id],
    );
    expect(audit.rows).toEqual([]);
  });

  it('lists today tasks and completes one once with an encrypted outcome note and chronology', async () => {
    const convert = await converts.create(parishActor, {
      fullName: 'Today Follow-up Convert',
      phone: '+234 803 000 0055',
      consent: { granted: true, version: '2026-11', method: 'DIGITAL' },
    });
    await testDatabase.pool.query(
      `UPDATE follow_up_tasks
       SET status = CASE WHEN task_type = 'CALL_24H' THEN 'PENDING'::follow_up_task_status
                         ELSE 'CANCELLED'::follow_up_task_status END,
           due_at = now(),
           completed_at = NULL,
           completed_by = NULL,
           outcome = NULL,
           outcome_note_encrypted = NULL
       WHERE convert_id = $1`,
      [convert.id],
    );

    const today = await followUpTasks.listToday(parishActor);
    const call = today.find((task) => task.convertId === convert.id);
    expect(call).toBeDefined();
    if (!call) {
      throw new Error('Expected the call task in the Today list.');
    }
    expect(call).toMatchObject({
      taskType: 'CALL_24H',
      occurrenceNumber: 1,
      convertName: 'Today Follow-up Convert',
      phone: '+2348030000055',
      status: 'PENDING',
    });

    await expect(
      followUpTasks.complete(parishActor, call.id, {
        outcome: 'NO_CONTACT',
        note: 'Called at the agreed time; no answer.',
      }),
    ).resolves.toMatchObject({
      id: call.id,
      status: 'COMPLETED',
      outcome: 'NO_CONTACT',
      note: 'Called at the agreed time; no answer.',
      completedBy: parishActor.id,
    });
    await expect(
      followUpTasks.complete(parishActor, call.id, { outcome: 'COMPLETED' }),
    ).rejects.toThrow(/already been resolved/i);
    await expect(followUpTasks.listToday(parishActor)).resolves.not.toContainEqual(
      expect.objectContaining({ id: call.id }),
    );

    const chronology = await testDatabase.pool.query<{
      event_type: string;
      metadata: Record<string, unknown>;
      note_encrypted: Buffer;
    }>(
      `SELECT event_type::text, metadata, note_encrypted
       FROM convert_timeline_events
       WHERE convert_id = $1 AND event_type = 'FOLLOW_UP_COMPLETED'`,
      [convert.id],
    );
    expect(chronology.rows).toHaveLength(1);
    expect(chronology.rows[0].event_type).toBe('FOLLOW_UP_COMPLETED');
    expect(chronology.rows[0].metadata['taskId']).toBe(call.id);
    expect(chronology.rows[0].metadata['outcome']).toBe('NO_CONTACT');
    expect(chronology.rows[0].note_encrypted.toString('utf8')).not.toContain('no answer');

    const audit = await testDatabase.pool.query<{
      action: string;
      metadata: Record<string, unknown>;
    }>(
      `SELECT action, metadata FROM audit_log
       WHERE resource_id = $1 AND action = 'FOLLOW_UP_TASK_COMPLETED'`,
      [call.id],
    );
    expect(audit.rows).toEqual([
      {
        action: 'FOLLOW_UP_TASK_COMPLETED',
        metadata: {
          taskType: 'CALL_24H',
          occurrenceNumber: 1,
          outcome: 'NO_CONTACT',
          noteRecorded: true,
        },
      },
    ]);
  });

  it('does not allow a Parish worker to complete a task outside that worker’s hierarchy scope', async () => {
    const convert = await converts.create(areaActor, {
      fullName: 'Other Parish Follow-up Convert',
      consent: { granted: true, version: '2026-11', method: 'DIGITAL' },
    });
    await converts.assignToParish(areaActor, convert.id, {
      parishId: units.get('NG-PAR-A')!.id,
    });
    const task = await testDatabase.pool.query<{ id: string }>(
      `SELECT id
       FROM follow_up_tasks
       WHERE convert_id = $1 AND task_type = 'CALL_24H'`,
      [convert.id],
    );
    await expect(
      followUpTasks.complete(parishActor, task.rows[0].id, { outcome: 'COMPLETED' }),
    ).rejects.toThrow(/not found in actor scope/i);
  });

  it('encrypts an active Android session FCM token before durable reminder delivery', async () => {
    const device = await testDatabase.pool.query<{ id: string }>(
      `INSERT INTO devices (user_id, device_identifier_hash, platform)
       VALUES ($1, $2, 'ANDROID') RETURNING id`,
      [parishActor.id, 'today-follow-up-android-device'],
    );
    await testDatabase.pool.query(
      `INSERT INTO sessions (id, user_id, device_id, refresh_token_hash, expires_at)
       VALUES ($1, $2, $3, $4, now() + interval '1 day')`,
      [
        parishActor.sessionId,
        parishActor.id,
        device.rows[0].id,
        'today-follow-up-android-refresh-token',
      ],
    );
    const token = 'fcm-registration-token-for-encrypted-storage-0123456789';
    await expect(followUpTasks.registerPushToken(parishActor, { token })).resolves.toEqual({
      registered: true,
    });
    const stored = await testDatabase.pool.query<{ push_token_encrypted: Buffer }>(
      `SELECT push_token_encrypted FROM devices WHERE id = $1`,
      [device.rows[0].id],
    );
    expect(stored.rows[0].push_token_encrypted.toString('utf8')).not.toContain(token);
    const audit = await testDatabase.pool.query<{
      action: string;
      metadata: Record<string, unknown>;
    }>(
      `SELECT action, metadata FROM audit_log
       WHERE resource_id = $1 AND action = 'FOLLOW_UP_PUSH_TOKEN_REGISTERED'`,
      [device.rows[0].id],
    );
    expect(audit.rows).toEqual([
      { action: 'FOLLOW_UP_PUSH_TOKEN_REGISTERED', metadata: { platform: 'ANDROID' } },
    ]);
  });

  it('masks phone numbers for above-Parish reads when the Global Admin switches the server setting', async () => {
    const convert = await converts.create(parishActor, {
      fullName: 'Phone Mask Convert',
      phone: '+234 803 000 0044',
      consent: { granted: true, version: '2026-11', method: 'DIGITAL' },
    });
    await expect(converts.get(areaActor, convert.id)).resolves.toMatchObject({
      phone: '+2348030000044',
    });
    await expect(privacySettings.getPhoneMasking(globalActor)).resolves.toEqual({
      maskPhoneNumbersAboveParish: false,
    });
    await expect(privacySettings.updatePhoneMasking(globalActor, true)).resolves.toEqual({
      maskPhoneNumbersAboveParish: true,
    });
    await expect(converts.get(areaActor, convert.id)).resolves.toMatchObject({ phone: '***0044' });
    await expect(converts.get(parishActor, convert.id)).resolves.toMatchObject({
      phone: '+2348030000044',
    });
  });
});
