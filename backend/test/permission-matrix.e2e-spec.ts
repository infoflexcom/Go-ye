import { ValidationPipe, type INestApplication } from '@nestjs/common';
import type { Server } from 'node:http';
import { createCipheriv, randomBytes } from 'node:crypto';
import { Test } from '@nestjs/testing';
import { JwtService } from '@nestjs/jwt';
import request from 'supertest';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { AppModule } from '../src/app.module.js';
import type { TestDatabase } from './support/embedded-postgres.js';
import { createTestDatabase } from './support/embedded-postgres.js';

const accessSecret = 'permission-matrix-access-secret-which-is-at-least-thirty-two-bytes';
const auditSecret = 'permission-matrix-audit-secret-which-is-at-least-thirty-two-bytes';
const piiKey = Buffer.alloc(32, 5);

function encryptPii(value: string): Buffer {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', piiKey, iv);
  const ciphertext = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
  return Buffer.concat([Buffer.from([1]), iv, cipher.getAuthTag(), ciphertext]);
}

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
  let reportConvertId: string;
  const jwt = new JwtService();

  beforeAll(async () => {
    database = await createTestDatabase();
    process.env.DATABASE_URL = database.connectionString;
    process.env.JWT_ACCESS_SECRET = accessSecret;
    process.env.OTP_PEPPER = 'permission-matrix-otp-pepper-which-is-at-least-thirty-two-bytes';
    process.env.AUDIT_CHAIN_SECRET = auditSecret;
    process.env.PII_ENCRYPTION_KEY = piiKey.toString('base64');
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
    await createActor('Privacy Officer', 'NG-ARE', 'PRIVACY_OFFICER');
    await createActor('Parish Alpha', 'NG-PAR-A', 'PARISH_PASTOR');
    await createActor('Parish Beta', 'NG-PAR-B', 'PARISH_PASTOR');

    const globalAdmin = actors.get('Global Admin');
    if (!globalAdmin) {
      throw new Error('Global Admin test actor was not created.');
    }
    const reportConvert = await database.pool.query<{ id: string }>(
      `INSERT INTO converts (
        full_name_encrypted, registered_at_unit_id, registered_by, parish_id,
        consent_granted, consent_version, consent_method, consent_captured_by, stage
      ) VALUES ($1, $2, $3, $4, true, '2026-11', 'DIGITAL', $3, 'NEW_CONVERT') RETURNING id`,
      [
        encryptPii('HTTP Reporting Convert'),
        units.get('NG-PAR-A')?.id,
        globalAdmin.userId,
        units.get('NG-PAR-A')?.id,
      ],
    );
    reportConvertId = reportConvert.rows[0].id;

    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('api/v1');
    app.useGlobalPipes(
      new ValidationPipe({ transform: true, whitelist: true, forbidNonWhitelisted: true }),
    );
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

  function removalRequestId(body: unknown): string {
    if (
      !body ||
      typeof body !== 'object' ||
      typeof (body as { requestId?: unknown }).requestId !== 'string'
    ) {
      throw new Error('Removal request response has no request ID.');
    }
    return (body as { requestId: string }).requestId;
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

  it('serves Global Admin country, region, grand-total and convert drill-down reports only to Global Admin', async () => {
    const countries = await request(httpServer())
      .get('/api/v1/admin/reports/countries')
      .set('Authorization', bearer('Global Admin'))
      .expect(200);
    expect(countries.body).toEqual([
      expect.objectContaining({ code: 'GH', total: 0 }),
      expect.objectContaining({ code: 'NG', total: 1 }),
    ]);

    const regions = await request(httpServer())
      .get(`/api/v1/admin/reports/countries/${units.get('NG')!.id}/regions`)
      .set('Authorization', bearer('Global Admin'))
      .expect(200);
    expect(regions.body).toEqual([expect.objectContaining({ code: 'NG-REG', total: 1 })]);

    await request(httpServer())
      .get(`/api/v1/admin/reports/countries/${units.get('NG')!.id}/total?stage=NEW_CONVERT`)
      .set('Authorization', bearer('Global Admin'))
      .expect(200)
      .expect(({ body }: { body: unknown }) => {
        expect(body).toEqual(expect.objectContaining({ countryCode: 'NG', total: 1 }));
      });
    await request(httpServer())
      .get('/api/v1/admin/reports/grand-total?stage=BAPTISED')
      .set('Authorization', bearer('Global Admin'))
      .expect(200)
      .expect(({ body }: { body: unknown }) => {
        expect(body).toEqual({ total: 0 });
      });

    const drillDown = await request(httpServer())
      .get(`/api/v1/admin/reports/countries/${units.get('NG')!.id}/converts?offset=0&limit=1`)
      .set('Authorization', bearer('Global Admin'))
      .expect(200);
    expect(drillDown.body).toMatchObject({
      total: 1,
      items: [
        expect.objectContaining({ fullName: 'HTTP Reporting Convert', stage: 'NEW_CONVERT' }),
      ],
    });
    await request(httpServer())
      .get(`/api/v1/admin/reports/countries/${units.get('NG')!.id}/converts?limit=101`)
      .set('Authorization', bearer('Global Admin'))
      .expect(400);

    await request(httpServer())
      .get('/api/v1/admin/reports/grand-total')
      .set('Authorization', bearer('Country Lead'))
      .expect(403);
    await request(httpServer())
      .get('/api/v1/privacy/settings/phone-masking')
      .set('Authorization', bearer('Global Admin'))
      .expect(200)
      .expect(({ body }: { body: unknown }) => {
        expect(body).toEqual({ maskPhoneNumbersAboveParish: false });
      });
    await request(httpServer())
      .patch('/api/v1/privacy/settings/phone-masking')
      .set('Authorization', bearer('Global Admin'))
      .send({ maskPhoneNumbersAboveParish: true })
      .expect(200)
      .expect(({ body }: { body: unknown }) => {
        expect(body).toEqual({ maskPhoneNumbersAboveParish: true });
      });
    await request(httpServer())
      .patch('/api/v1/privacy/settings/phone-masking')
      .set('Authorization', bearer('Country Lead'))
      .send({ maskPhoneNumbersAboveParish: false })
      .expect(403);
  });

  it('quarantines requests over HTTP and restricts resolution to the scoped Privacy Officer', async () => {
    const removal = await request(httpServer())
      .post(`/api/v1/converts/${reportConvertId}/removal-requests`)
      .set('Authorization', bearer('Parish Alpha'))
      .send({ reason: 'The convert requested deletion.' })
      .expect(201);
    expect(removal.body).toEqual(expect.objectContaining({ status: 'PENDING' }));
    const requestId = removalRequestId(removal.body as unknown);

    await request(httpServer())
      .get('/api/v1/privacy/removal-requests')
      .set('Authorization', bearer('Country Lead'))
      .expect(403);
    const pending = await request(httpServer())
      .get('/api/v1/privacy/removal-requests?status=PENDING')
      .set('Authorization', bearer('Privacy Officer'))
      .expect(200);
    expect(pending.body).toEqual([
      expect.objectContaining({
        id: requestId,
        convertId: reportConvertId,
        reason: 'The convert requested deletion.',
      }),
    ]);

    await request(httpServer())
      .post(`/api/v1/privacy/removal-requests/${requestId}/resolve`)
      .set('Authorization', bearer('Privacy Officer'))
      .send({ outcome: 'ANONYMISE', note: 'Identity confirmed.' })
      .expect(201)
      .expect(({ body }: { body: unknown }) => {
        expect(body).toEqual({ convertId: reportConvertId, status: 'ANONYMISED' });
      });
    await request(httpServer())
      .get(`/api/v1/converts/${reportConvertId}`)
      .set('Authorization', bearer('Global Admin'))
      .expect(404);
  });
});
