import { ConfigService } from '@nestjs/config';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { AdminService } from '../src/admin/admin.service.js';
import { AuditService } from '../src/audit/audit.service.js';
import type { AuthenticatedActor } from '../src/authorization/authorization.types.js';
import { DatabaseService } from '../src/database/database.service.js';
import type { TestDatabase } from './support/embedded-postgres.js';
import { createTestDatabase } from './support/embedded-postgres.js';

const auditSecret = 'admin-test-audit-secret-which-is-at-least-thirty-two-bytes';

describe('AdminService', () => {
  let testDatabase: TestDatabase;
  let database: DatabaseService;
  let admin: AdminService;
  let actor: AuthenticatedActor;

  beforeAll(async () => {
    testDatabase = await createTestDatabase();
    const config = new ConfigService({
      DATABASE_URL: testDatabase.connectionString,
      AUDIT_CHAIN_SECRET: auditSecret,
    });
    database = new DatabaseService(config);
    admin = new AdminService(database, new AuditService(), config);

    const globalUser = await testDatabase.pool.query<{ id: string }>(
      `INSERT INTO users (display_name, email_normalized, status)
       VALUES ('Global Admin', 'global.admin@example.test', 'ACTIVE') RETURNING id`,
    );
    await testDatabase.pool.query(
      `INSERT INTO user_roles (user_id, role_id, assigned_by)
       SELECT $1, id, $1 FROM roles WHERE key = 'GLOBAL_ADMIN'`,
      [globalUser.rows[0].id],
    );
    actor = {
      id: globalUser.rows[0].id,
      sessionId: '00000000-0000-0000-0000-000000000001',
      roles: ['GLOBAL_ADMIN'],
      isGlobalAdmin: true,
    };
  }, 30_000);

  afterAll(async () => {
    await database.onModuleDestroy();
    await testDatabase.close();
  });

  it('creates, moves and audits a complete subtree with rebuilt descendant paths', async () => {
    const country = await admin.createOrgUnit(actor, {
      type: 'COUNTRY',
      name: 'Nigeria',
      code: 'NG',
    });
    const region = await admin.createOrgUnit(actor, {
      type: 'REGION',
      name: 'Lagos Region',
      code: 'NG-REG',
      parentId: country.id,
    });
    const province = await admin.createOrgUnit(actor, {
      type: 'PROVINCE',
      name: 'Province One',
      code: 'NG-PRO',
      parentId: region.id,
    });
    const zoneOne = await admin.createOrgUnit(actor, {
      type: 'ZONE',
      name: 'Zone One',
      code: 'NG-ZON-1',
      parentId: province.id,
    });
    const zoneTwo = await admin.createOrgUnit(actor, {
      type: 'ZONE',
      name: 'Zone Two',
      code: 'NG-ZON-2',
      parentId: province.id,
    });
    const area = await admin.createOrgUnit(actor, {
      type: 'AREA',
      name: 'Area One',
      code: 'NG-ARE-1',
      parentId: zoneOne.id,
    });
    const parish = await admin.createOrgUnit(actor, {
      type: 'PARISH',
      name: 'Parish Alpha',
      code: 'NG-PAR-A',
      parentId: area.id,
    });
    const oldAreaPath = area.path;
    const oldParishPath = parish.path;

    const move = await admin.moveOrgUnit(actor, area.id, { newParentId: zoneTwo.id });
    expect(move.movedDescendantCount).toBe(2);
    expect(move.oldPath).toBe(oldAreaPath);
    expect(move.newPath).toBe(`${zoneTwo.path}.u${area.id.replaceAll('-', '')}`);

    const subtree = await testDatabase.pool.query<{
      code: string;
      path: string;
      parent_id: string | null;
    }>(
      `SELECT code, path::text, parent_id FROM org_units
       WHERE code IN ('NG-ARE-1', 'NG-PAR-A') ORDER BY code`,
    );
    expect(subtree.rows).toEqual([
      { code: 'NG-ARE-1', path: move.newPath, parent_id: zoneTwo.id },
      {
        code: 'NG-PAR-A',
        path: `${move.newPath}.u${parish.id.replaceAll('-', '')}`,
        parent_id: area.id,
      },
    ]);
    expect(subtree.rows[1].path).not.toBe(oldParishPath);

    const audit = await testDatabase.pool.query<{
      action: string;
      metadata: { movedDescendantCount: number };
    }>(`SELECT action, metadata FROM audit_log WHERE action = 'ORG_UNIT_MOVED'`);
    expect(audit.rows).toHaveLength(1);
    expect(audit.rows[0].metadata.movedDescendantCount).toBe(2);
  });

  it('manages users and roles while enforcing Global Admin and home-unit invariants', async () => {
    const parish = await testDatabase.pool.query<{ id: string }>(
      `SELECT id FROM org_units WHERE code = 'NG-PAR-A'`,
    );
    const created = await admin.createUser(actor, {
      displayName: 'Parish Worker',
      phone: '+2348030000001',
      homeUnitId: parish.rows[0].id,
      roles: ['SOUL_WINNER'],
    });
    expect(created.roles).toEqual(['SOUL_WINNER']);

    const elevated = await admin.addRole(actor, created.id, 'FOLLOW_UP_WORKER');
    expect(elevated.roles).toEqual(['FOLLOW_UP_WORKER', 'SOUL_WINNER']);
    const reduced = await admin.removeRole(actor, created.id, 'SOUL_WINNER');
    expect(reduced.roles).toEqual(['FOLLOW_UP_WORKER']);

    await expect(
      admin.createUser(actor, {
        displayName: 'Invalid Global',
        email: 'invalid.global@example.test',
        homeUnitId: parish.rows[0].id,
        roles: ['GLOBAL_ADMIN'],
      }),
    ).rejects.toThrow(/must not have a home unit/i);

    await expect(
      admin.updateOrgUnit(actor, (await admin.getOrgUnit(actor, parish.rows[0].id)).parent_id!, {
        isActive: false,
      }),
    ).rejects.toThrow(/deactivate child units/i);
  });
});
