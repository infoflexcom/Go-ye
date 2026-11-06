import { ConfigService } from '@nestjs/config';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { DatabaseService } from '../src/database/database.service.js';
import type { DatabaseActor } from '../src/database/database.service.js';
import type { TestDatabase } from './support/embedded-postgres.js';
import { createTestDatabase } from './support/embedded-postgres.js';

interface UnitRow {
  id: string;
  code: string;
  path: string;
}

interface UserRow {
  id: string;
  display_name: string;
}

describe('row-level security home-unit descendant scope', () => {
  let testDatabase: TestDatabase;
  let database: DatabaseService;
  const units = new Map<string, UnitRow>();
  const users = new Map<string, UserRow>();

  beforeAll(async () => {
    testDatabase = await createTestDatabase();
    database = new DatabaseService(
      new ConfigService({ DATABASE_URL: testDatabase.connectionString }),
    );

    async function createUnit(
      type: string,
      name: string,
      code: string,
      parentCode?: string,
    ): Promise<UnitRow> {
      const result = await testDatabase.pool.query<UnitRow>(
        `INSERT INTO org_units (type, name, code, parent_id)
         VALUES ($1::org_unit_type, $2, $3, $4)
         RETURNING id, code, path::text`,
        [type, name, code, parentCode ? units.get(parentCode)?.id : null],
      );
      const unit = result.rows[0];
      units.set(code, unit);
      return unit;
    }

    await createUnit('COUNTRY', 'Nigeria', 'NG');
    await createUnit('REGION', 'Lagos Region', 'NG-REG-1', 'NG');
    await createUnit('PROVINCE', 'Province One', 'NG-PRO-1', 'NG-REG-1');
    await createUnit('ZONE', 'Zone One', 'NG-ZON-1', 'NG-PRO-1');
    await createUnit('AREA', 'Area One', 'NG-ARE-1', 'NG-ZON-1');
    await createUnit('PARISH', 'Parish Alpha', 'NG-PAR-A', 'NG-ARE-1');
    await createUnit('PARISH', 'Parish Beta', 'NG-PAR-B', 'NG-ARE-1');
    await createUnit('COUNTRY', 'Ghana', 'GH');
    await createUnit('REGION', 'Accra Region', 'GH-REG-1', 'GH');

    async function createUser(name: string, homeCode?: string): Promise<void> {
      const result = await testDatabase.pool.query<UserRow>(
        `INSERT INTO users (display_name, email_normalized, home_unit_id, status)
         VALUES ($1, $2, $3, 'ACTIVE')
         RETURNING id, display_name`,
        [
          name,
          `${name.toLowerCase().replaceAll(' ', '.')}@example.test`,
          homeCode ? units.get(homeCode)?.id : null,
        ],
      );
      users.set(name, result.rows[0]);
    }

    await createUser('Global Admin');
    await createUser('Nigeria Country', 'NG');
    await createUser('Lagos Region', 'NG-REG-1');
    await createUser('Province One', 'NG-PRO-1');
    await createUser('Zone One', 'NG-ZON-1');
    await createUser('Area One', 'NG-ARE-1');
    await createUser('Parish Alpha', 'NG-PAR-A');
    await createUser('Parish Beta', 'NG-PAR-B');
    await createUser('Ghana Country', 'GH');
  }, 30_000);

  afterAll(async () => {
    await database.onModuleDestroy();
    await testDatabase.close();
  });

  function actor(name: string, homeCode: string, isGlobalAdmin = false): DatabaseActor {
    return {
      userId: users.get(name)?.id,
      homePath: units.get(homeCode)?.path,
      isGlobalAdmin,
    };
  }

  async function visibleCodes(context: DatabaseActor): Promise<string[]> {
    return database.withActor(context, async (client) => {
      const result = await client.query<{ code: string }>(
        'SELECT code FROM org_units ORDER BY code',
      );
      return result.rows.map((row) => row.code);
    });
  }

  it('limits a parish actor to the parish itself and blocks ID-guessing outside it', async () => {
    const parishActor = actor('Parish Alpha', 'NG-PAR-A');
    await expect(visibleCodes(parishActor)).resolves.toEqual(['NG-PAR-A']);

    const guessedGhana = await database.withActor(parishActor, (client) =>
      client.query<{ id: string }>('SELECT id FROM org_units WHERE id = $1', [units.get('GH')?.id]),
    );
    expect(guessedGhana.rows).toEqual([]);

    const visibleUsers = await database.withActor(parishActor, async (client) => {
      const result = await client.query<UserRow>(
        'SELECT id, display_name FROM users ORDER BY display_name',
      );
      return result.rows.map((row) => row.display_name);
    });
    expect(visibleUsers).toEqual(['Parish Alpha']);
  });

  it('returns the home unit and exact descendants at each hierarchy level', async () => {
    await expect(visibleCodes(actor('Area One', 'NG-ARE-1'))).resolves.toEqual([
      'NG-ARE-1',
      'NG-PAR-A',
      'NG-PAR-B',
    ]);
    await expect(visibleCodes(actor('Zone One', 'NG-ZON-1'))).resolves.toEqual([
      'NG-ARE-1',
      'NG-PAR-A',
      'NG-PAR-B',
      'NG-ZON-1',
    ]);
    await expect(visibleCodes(actor('Province One', 'NG-PRO-1'))).resolves.toEqual([
      'NG-ARE-1',
      'NG-PAR-A',
      'NG-PAR-B',
      'NG-PRO-1',
      'NG-ZON-1',
    ]);
    await expect(visibleCodes(actor('Lagos Region', 'NG-REG-1'))).resolves.toEqual([
      'NG-ARE-1',
      'NG-PAR-A',
      'NG-PAR-B',
      'NG-PRO-1',
      'NG-REG-1',
      'NG-ZON-1',
    ]);
    await expect(visibleCodes(actor('Nigeria Country', 'NG'))).resolves.toEqual([
      'NG',
      'NG-ARE-1',
      'NG-PAR-A',
      'NG-PAR-B',
      'NG-PRO-1',
      'NG-REG-1',
      'NG-ZON-1',
    ]);
  });

  it('lets a Global Admin see every country independently and every descendant', async () => {
    const global = {
      userId: users.get('Global Admin')?.id,
      isGlobalAdmin: true,
    };
    await expect(visibleCodes(global)).resolves.toEqual([
      'GH',
      'GH-REG-1',
      'NG',
      'NG-ARE-1',
      'NG-PAR-A',
      'NG-PAR-B',
      'NG-PRO-1',
      'NG-REG-1',
      'NG-ZON-1',
    ]);
  });

  it('does not expose protected audit records outside system or Global Admin context', async () => {
    const regularAuditRead = await database.withActor(actor('Area One', 'NG-ARE-1'), (client) =>
      client.query('SELECT * FROM audit_log'),
    );
    expect(regularAuditRead.rows).toEqual([]);
  });
});
