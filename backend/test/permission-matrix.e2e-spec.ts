import type { INestApplication } from '@nestjs/common';
import type { Server } from 'node:http';
import { Test } from '@nestjs/testing';
import { JwtService } from '@nestjs/jwt';
import request from 'supertest';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { AppModule } from '../src/app.module.js';
import type { TestDatabase } from './support/embedded-postgres.js';
import { createTestDatabase } from './support/embedded-postgres.js';

const accessSecret = 'permission-matrix-access-secret-which-is-at-least-thirty-two-bytes';
const auditSecret = 'permission-matrix-audit-secret-which-is-at-least-thirty-two-bytes';

interface Unit {
  id: string;
  code: string;
  path: string;
}

interface ActorToken {
  userId: string;
  token: string;
}

describe('permission test matrix (HTTP + RLS)', () => {
  let database: TestDatabase;
  let app: INestApplication;
  const units = new Map<string, Unit>();
  const actors = new Map<string, ActorToken>();
  const jwt = new JwtService();

  beforeAll(async () => {
    database = await createTestDatabase();
    process.env.DATABASE_URL = database.connectionString;
    process.env.JWT_ACCESS_SECRET = accessSecret;
    process.env.OTP_PEPPER = 'permission-matrix-otp-pepper-which-is-at-least-thirty-two-bytes';
    process.env.AUDIT_CHAIN_SECRET = auditSecret;
    process.env.NODE_ENV = 'test';

    async function createUnit(type: string, code: string, parentCode?: string): Promise<void> {
      const result = await database.pool.query<Unit>(
        `INSERT INTO org_units (type, name, code, parent_id)
         VALUES ($1::org_unit_type, $2, $3, $4)
         RETURNING id, code, path::text`,
        [type, code, code, parentCode ? units.get(parentCode)?.id : null],
      );
      units.set(code, result.rows[0]);
    }

    await createUnit('COUNTRY', 'NG');
    await createUnit('REGION', 'NG-REG', 'NG');
    await createUnit('PROVINCE', 'NG-PRO', 'NG-REG');
    await createUnit('ZONE', 'NG-ZON', 'NG-PRO');
    await createUnit('AREA', 'NG-ARE', 'NG-ZON');
    await createUnit('PARISH', 'NG-PAR-A', 'NG-ARE');
    await createUnit('PARISH', 'NG-PAR-B', 'NG-ARE');
    await createUnit('COUNTRY', 'GH');
    await createUnit('REGION', 'GH-REG', 'GH');

    async function createActor(
      name: string,
      homeCode: string | undefined,
      role: string,
    ): Promise<void> {
      const user = await database.pool.query<{ id: string }>(
        `INSERT INTO users (display_name, email_normalized, home_unit_id, status)
         VALUES ($1, $2, $3, 'ACTIVE') RETURNING id`,
        [
          name,
          `${name.toLowerCase().replaceAll(' ', '.')}@matrix.test`,
          homeCode ? units.get(homeCode)?.id : null,
        ],
      );
      await database.pool.query(
        `INSERT INTO user_roles (user_id, role_id, assigned_by)
         SELECT $1, id, $1 FROM roles WHERE key = $2`,
        [user.rows[0].id, role],
      );
      const session = await database.pool.query<{ id: string }>(
        `INSERT INTO sessions (user_id, refresh_token_hash, expires_at)
         VALUES ($1, $2, now() + interval '1 hour') RETURNING id`,
        [user.rows[0].id, `matrix-${name}`],
      );
      const token = await jwt.signAsync(
        { sub: user.rows[0].id, sid: session.rows[0].id, roles: [role] },
        { secret: accessSecret, issuer: 'goye-api', audience: 'goye-client', expiresIn: 900 },
      );
      actors.set(name, { userId: user.rows[0].id, token });
    }

    await createActor('Global Admin', undefined, 'GLOBAL_ADMIN');
    await createActor('Country Lead', 'NG', 'COUNTRY_ADMIN');
    await createActor('Region Lead', 'NG-REG', 'REGION_LEADER');
    await createActor('Province Lead', 'NG-PRO', 'PROVINCE_LEADER');
    await createActor('Zone Lead', 'NG-ZON', 'ZONE_LEADER');
    await createActor('Area Lead', 'NG-ARE', 'AREA_LEADER');
    await createActor('Parish Alpha', 'NG-PAR-A', 'PARISH_PASTOR');
    await createActor('Parish Beta', 'NG-PAR-B', 'PARISH_PASTOR');

    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('api/v1');
    await app.init();
  }, 30_000);

  afterAll(async () => {
    await app?.close();
    await database.close();
  });

  function bearer(name: string): string {
    return `Bearer ${actors.get(name)?.token}`;
  }

  function httpServer(): Server {
    return app.getHttpServer() as Server;
  }

  function codesFromResponse(body: unknown): string[] {
    if (!Array.isArray(body)) {
      throw new Error('Directory response is not an array.');
    }
    return body.map((unit: unknown) => {
      if (
        !unit ||
        typeof unit !== 'object' ||
        typeof (unit as { code?: unknown }).code !== 'string'
      ) {
        throw new Error('Directory response contains an invalid unit.');
      }
      return (unit as { code: string }).code;
    });
  }

  async function visibleCodes(name: string): Promise<string[]> {
    const response = await request(httpServer())
      .get('/api/v1/directory/org-units')
      .set('Authorization', bearer(name))
      .expect(200);
    return codesFromResponse(response.body as unknown);
  }

  async function expectVisibleCodes(name: string, expected: string[]): Promise<void> {
    expect((await visibleCodes(name)).sort()).toEqual(expected.sort());
  }

  it('parish actor sees only its own parish and cannot guess another parish or user ID', async () => {
    await expectVisibleCodes('Parish Alpha', ['NG-PAR-A']);
    await request(httpServer())
      .get(`/api/v1/directory/org-units/${units.get('GH')?.id}`)
      .set('Authorization', bearer('Parish Alpha'))
      .expect(404);
    await request(httpServer())
      .get(`/api/v1/directory/users/${actors.get('Parish Beta')?.userId}`)
      .set('Authorization', bearer('Parish Alpha'))
      .expect(404);
  });

  it('area actor sees its area and exactly its parishes', async () => {
    await expectVisibleCodes('Area Lead', ['NG-ARE', 'NG-PAR-A', 'NG-PAR-B']);
  });

  it('each upper hierarchy level sees exactly its home unit and descendants', async () => {
    await expectVisibleCodes('Zone Lead', ['NG-ZON', 'NG-ARE', 'NG-PAR-A', 'NG-PAR-B']);
    await expectVisibleCodes('Province Lead', [
      'NG-PRO',
      'NG-ZON',
      'NG-ARE',
      'NG-PAR-A',
      'NG-PAR-B',
    ]);
    await expectVisibleCodes('Region Lead', [
      'NG-REG',
      'NG-PRO',
      'NG-ZON',
      'NG-ARE',
      'NG-PAR-A',
      'NG-PAR-B',
    ]);
    await expectVisibleCodes('Country Lead', [
      'NG',
      'NG-REG',
      'NG-PRO',
      'NG-ZON',
      'NG-ARE',
      'NG-PAR-A',
      'NG-PAR-B',
    ]);
  });

  it('Global Admin sees all countries and their descendants', async () => {
    await expectVisibleCodes('Global Admin', [
      'NG',
      'NG-REG',
      'NG-PRO',
      'NG-ZON',
      'NG-ARE',
      'NG-PAR-A',
      'NG-PAR-B',
      'GH',
      'GH-REG',
    ]);
  });

  it('returns 403 for a non-admin attempt to enter Global Admin APIs', async () => {
    await request(httpServer())
      .get(`/api/v1/admin/org-units/${units.get('NG')?.id}`)
      .set('Authorization', bearer('Parish Alpha'))
      .expect(403);
  });
});
