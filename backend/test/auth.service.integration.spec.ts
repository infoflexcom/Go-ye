import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { AuditService } from '../src/audit/audit.service.js';
import { AuthService } from '../src/auth/auth.service.js';
import type { OtpDeliveryMessage, OtpDeliveryService } from '../src/auth/auth.types.js';
import { DatabaseService } from '../src/database/database.service.js';
import type { TestDatabase } from './support/embedded-postgres.js';
import { createTestDatabase } from './support/embedded-postgres.js';

const secrets = {
  JWT_ACCESS_SECRET: 'auth-test-access-secret-which-is-at-least-thirty-two-bytes',
  JWT_REFRESH_SECRET: 'auth-test-refresh-secret-which-is-at-least-thirty-two-bytes',
  OTP_PEPPER: 'auth-test-otp-pepper-which-is-at-least-thirty-two-bytes',
  AUDIT_CHAIN_SECRET: 'auth-test-audit-secret-which-is-at-least-thirty-two-bytes',
  OTP_TTL_SECONDS: 600,
  OTP_MAX_ATTEMPTS: 2,
  OTP_LOCKOUT_SECONDS: 900,
  OTP_SEND_LIMIT_PER_PHONE_PER_HOUR: 2,
  OTP_SEND_LIMIT_PER_IP_PER_HOUR: 8,
  JWT_ACCESS_TTL_SECONDS: 900,
  JWT_REFRESH_TTL_SECONDS: 3600,
};

class CapturingOtpDeliveryService implements OtpDeliveryService {
  readonly messages: OtpDeliveryMessage[] = [];

  send(message: OtpDeliveryMessage): Promise<void> {
    this.messages.push(message);
    return Promise.resolve();
  }
}

describe('AuthService', () => {
  let testDatabase: TestDatabase;
  let database: DatabaseService;
  let delivery: CapturingOtpDeliveryService;
  let auth: AuthService;
  let jwt: JwtService;
  let sequence = 0;

  beforeAll(async () => {
    testDatabase = await createTestDatabase();
    const config = new ConfigService({
      DATABASE_URL: testDatabase.connectionString,
      ...secrets,
    });
    database = new DatabaseService(config);
    jwt = new JwtService();
    delivery = new CapturingOtpDeliveryService();
    auth = new AuthService(database, config, jwt, new AuditService(), delivery);
  }, 30_000);

  beforeEach(() => {
    delivery.messages.length = 0;
    sequence += 1;
  });

  afterAll(async () => {
    await database.onModuleDestroy();
    await testDatabase.close();
  });

  async function createUser(): Promise<{ id: string; phone: string }> {
    const phone = `+234801${String(sequence).padStart(7, '0')}`;
    const result = await testDatabase.pool.query<{ id: string }>(
      `INSERT INTO users (phone_normalized, display_name, status)
       VALUES ($1, $2, 'ACTIVE')
       RETURNING id`,
      [phone, `Test user ${sequence}`],
    );
    return { id: result.rows[0].id, phone };
  }

  it('issues a short-lived JWT and rotates an opaque refresh token after a valid OTP', async () => {
    const user = await createUser();
    await expect(
      auth.requestOtp(
        { identity: user.phone, deviceIdentifier: 'device-auth-0001' },
        '203.0.113.4',
      ),
    ).resolves.toEqual({ accepted: true });
    expect(delivery.messages).toHaveLength(1);
    expect(delivery.messages[0].code).toMatch(/^\d{6}$/);

    const persistedChallenge = await testDatabase.pool.query<{ code_hash: string }>(
      'SELECT code_hash FROM otp_challenges ORDER BY created_at DESC LIMIT 1',
    );
    expect(persistedChallenge.rows[0].code_hash).not.toContain(delivery.messages[0].code);

    const tokens = await auth.verifyOtp(
      {
        identity: user.phone,
        code: delivery.messages[0].code,
        deviceIdentifier: 'device-auth-0001',
        platform: 'ANDROID',
      },
      '203.0.113.4',
    );
    expect(tokens.accessToken).not.toEqual(tokens.refreshToken);
    const claims = await jwt.verifyAsync<{ sub: string; sid: string }>(tokens.accessToken, {
      secret: secrets.JWT_ACCESS_SECRET,
      issuer: 'goye-api',
      audience: 'goye-client',
    });
    expect(claims.sub).toBe(user.id);

    const rotated = await auth.refresh({ refreshToken: tokens.refreshToken }, '203.0.113.4');
    expect(rotated.refreshToken).not.toBe(tokens.refreshToken);

    await expect(
      auth.refresh({ refreshToken: tokens.refreshToken }, '203.0.113.4'),
    ).rejects.toThrow(/refresh token is invalid/i);
    const sessions = await testDatabase.pool.query<{
      status: string;
      revoked_reason: string | null;
    }>('SELECT status, revoked_reason FROM sessions WHERE user_id = $1 ORDER BY issued_at', [
      user.id,
    ]);
    expect(sessions.rows.some((session) => session.revoked_reason === 'REFRESH_TOKEN_REUSE')).toBe(
      true,
    );
  });

  it('locks an identity after the configured count of invalid OTP attempts', async () => {
    const user = await createUser();
    await auth.requestOtp({ identity: user.phone }, '203.0.113.5');

    const verification = {
      identity: user.phone,
      code: '000000',
      deviceIdentifier: 'device-auth-0002',
      platform: 'WINDOWS' as const,
    };
    await expect(auth.verifyOtp(verification, '203.0.113.5')).rejects.toThrow(
      /invalid, expired, or locked/i,
    );
    await expect(auth.verifyOtp(verification, '203.0.113.5')).rejects.toThrow(
      /invalid, expired, or locked/i,
    );
    await expect(auth.requestOtp({ identity: user.phone }, '203.0.113.5')).rejects.toThrow(
      /temporarily locked/i,
    );
  });

  it('enforces the per-identity OTP send rate limit', async () => {
    const user = await createUser();
    await auth.requestOtp({ identity: user.phone }, '203.0.113.6');
    await auth.requestOtp({ identity: user.phone }, '203.0.113.6');
    await expect(auth.requestOtp({ identity: user.phone }, '203.0.113.6')).rejects.toThrow(
      /too many otp requests/i,
    );
  });
});
