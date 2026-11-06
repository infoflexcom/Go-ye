import {
  Inject,
  Injectable,
  HttpException,
  HttpStatus,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import type { PoolClient } from 'pg';
import { AuditService } from '../audit/audit.service.js';
import { DatabaseService } from '../database/database.service.js';
import {
  keyedHash,
  normalizeIdentity,
  randomOtp,
  randomRefreshToken,
  secretHash,
  verifySecret,
} from './auth.identity.js';
import {
  OTP_DELIVERY_SERVICE,
  type AccessTokenPayload,
  type AuthTokens,
  type OtpDeliveryService,
} from './auth.types.js';
import type { RefreshTokenDto } from './dto/refresh-token.dto.js';
import type { RequestOtpDto } from './dto/request-otp.dto.js';
import type { VerifyOtpDto } from './dto/verify-otp.dto.js';

interface AuthUserRow {
  id: string;
  status: 'ACTIVE' | 'INVITED' | 'SUSPENDED' | 'DEACTIVATED';
  home_unit_id: string | null;
  home_path: string | null;
  roles: string[];
}

interface OtpChallengeRow {
  id: string;
  user_id: string | null;
  code_hash: string;
  attempts: number;
  max_attempts: number;
}

interface SessionUserRow extends AuthUserRow {
  session_id: string;
  device_id: string | null;
  session_status: 'ACTIVE' | 'REVOKED' | 'EXPIRED';
  expires_at: Date;
  revoked_reason: string | null;
}

@Injectable()
export class AuthService {
  constructor(
    private readonly database: DatabaseService,
    private readonly config: ConfigService,
    private readonly jwt: JwtService,
    private readonly audit: AuditService,
    @Inject(OTP_DELIVERY_SERVICE) private readonly otpDelivery: OtpDeliveryService,
  ) {}

  async requestOtp(dto: RequestOtpDto, ipAddress?: string): Promise<{ accepted: true }> {
    const identity = normalizeIdentity(dto.identity);
    const pepper = this.requiredSecret('OTP_PEPPER');
    const destinationHash = keyedHash(identity.destination, pepper);
    const ipHash = ipAddress ? keyedHash(ipAddress, pepper) : null;
    const deviceHash = dto.deviceIdentifier ? keyedHash(dto.deviceIdentifier, pepper) : null;
    const code = randomOtp();

    await this.database.withActor(this.systemActor(), async (client) => {
      const user = await this.findUserByIdentity(client, identity.destination, identity.channel);
      // Deliberately return a generic accepted response for unknown, suspended and deactivated identities.
      if (!user || user.status === 'SUSPENDED' || user.status === 'DEACTIVATED') {
        return;
      }

      await this.enforceOtpRateLimits(client, destinationHash, ipHash);
      const codeHash = await secretHash(code);
      const expiresInSeconds = this.numberSetting('OTP_TTL_SECONDS', 600);
      await client.query(
        `INSERT INTO otp_challenges (
          user_id, channel, destination_hash, code_hash, max_attempts, expires_at, request_ip_hash, device_identifier_hash
        ) VALUES ($1, $2, $3, $4, $5, now() + ($6 * interval '1 second'), $7, $8)`,
        [
          user.id,
          identity.channel,
          destinationHash,
          codeHash,
          this.numberSetting('OTP_MAX_ATTEMPTS', 5),
          expiresInSeconds,
          ipHash,
          deviceHash,
        ],
      );
      await this.otpDelivery.send({
        destination: identity.destination,
        channel: identity.channel,
        code,
        expiresInSeconds,
      });
      await this.audit.append(client, {
        actorUserId: user.id,
        action: 'AUTH_OTP_REQUESTED',
        resourceType: 'USER',
        resourceId: user.id,
        scopeUnitId: user.home_unit_id ?? undefined,
        metadata: { channel: identity.channel },
      });
    });

    return { accepted: true };
  }

  async verifyOtp(dto: VerifyOtpDto, ipAddress?: string): Promise<AuthTokens> {
    const identity = normalizeIdentity(dto.identity);
    const pepper = this.requiredSecret('OTP_PEPPER');
    const destinationHash = keyedHash(identity.destination, pepper);
    const ipHash = ipAddress ? keyedHash(ipAddress, pepper) : null;
    const deviceHash = keyedHash(dto.deviceIdentifier, pepper);

    const tokens = await this.database.withActor(this.systemActor(), async (client) => {
      const challenge = await this.currentChallenge(client, destinationHash, identity.channel);
      if (!challenge || !challenge.user_id) {
        return null;
      }

      const matches = await verifySecret(dto.code, challenge.code_hash);
      if (!matches) {
        const nextAttempts = challenge.attempts + 1;
        await client.query(
          `UPDATE otp_challenges
           SET attempts = $1, locked_at = CASE WHEN $1 >= max_attempts THEN now() ELSE locked_at END
           WHERE id = $2`,
          [nextAttempts, challenge.id],
        );
        if (nextAttempts >= challenge.max_attempts) {
          await client.query(
            `INSERT INTO auth_lockouts (destination_hash, locked_until, failed_attempts)
             VALUES ($1, now() + ($2 * interval '1 second'), $3)
             ON CONFLICT (destination_hash) DO UPDATE
             SET locked_until = EXCLUDED.locked_until,
                 failed_attempts = auth_lockouts.failed_attempts + 1,
                 updated_at = now()`,
            [destinationHash, this.numberSetting('OTP_LOCKOUT_SECONDS', 900), nextAttempts],
          );
        }
        return null;
      }

      const user = await this.findUserById(client, challenge.user_id);
      if (!user || user.status === 'SUSPENDED' || user.status === 'DEACTIVATED') {
        return null;
      }

      await client.query('UPDATE otp_challenges SET consumed_at = now() WHERE id = $1', [
        challenge.id,
      ]);
      await client.query(
        `UPDATE users
         SET status = CASE WHEN status = 'INVITED' THEN 'ACTIVE'::user_status ELSE status END,
             last_login_at = now(), updated_at = now()
         WHERE id = $1`,
        [user.id],
      );
      const device = await client.query<{ id: string }>(
        `INSERT INTO devices (user_id, device_identifier_hash, platform, label, last_seen_at)
         VALUES ($1, $2, $3, $4, now())
         ON CONFLICT (user_id, device_identifier_hash)
         DO UPDATE SET platform = EXCLUDED.platform, label = EXCLUDED.label,
                       last_seen_at = now(), revoked_at = NULL, updated_at = now()
         RETURNING id`,
        [user.id, deviceHash, dto.platform, dto.deviceLabel ?? null],
      );
      const sessionId = await this.createSession(client, user.id, device.rows[0].id, ipHash);
      const issuedTokens = await this.issueTokens(user, sessionId, client);
      await this.audit.append(client, {
        actorUserId: user.id,
        action: 'AUTH_LOGIN_SUCCEEDED',
        resourceType: 'SESSION',
        resourceId: sessionId,
        scopeUnitId: user.home_unit_id ?? undefined,
        metadata: { channel: identity.channel, platform: dto.platform },
      });
      return issuedTokens;
    });

    if (!tokens) {
      throw new UnauthorizedException('The code is invalid, expired, or locked.');
    }
    return tokens;
  }

  async refresh(dto: RefreshTokenDto, ipAddress?: string): Promise<AuthTokens> {
    const pepper = this.requiredSecret('OTP_PEPPER');
    const refreshHash = keyedHash(dto.refreshToken, pepper);
    const ipHash = ipAddress ? keyedHash(ipAddress, pepper) : null;

    const tokens = await this.database.withActor(this.systemActor(), async (client) => {
      const session = await client.query<SessionUserRow>(
        `SELECT s.id AS session_id, s.device_id, s.status AS session_status, s.expires_at, s.revoked_reason,
                u.id, u.status, u.home_unit_id, h.path::text AS home_path,
                COALESCE((
                  SELECT array_agg(role_lookup.key ORDER BY role_lookup.key)
                  FROM user_roles role_assignment
                  JOIN roles role_lookup ON role_lookup.id = role_assignment.role_id
                  WHERE role_assignment.user_id = u.id
                ), ARRAY[]::text[]) AS roles
         FROM sessions s
         JOIN users u ON u.id = s.user_id
         LEFT JOIN org_units h ON h.id = u.home_unit_id
         WHERE s.refresh_token_hash = $1
         FOR UPDATE OF s`,
        [refreshHash],
      );
      const current = session.rows[0];
      if (!current) {
        return null;
      }
      if (current.session_status !== 'ACTIVE' || current.expires_at <= new Date()) {
        if (current.session_status === 'REVOKED' && current.revoked_reason === 'ROTATED') {
          await client.query(
            `UPDATE sessions
             SET status = 'REVOKED', revoked_at = now(), revoked_reason = 'REFRESH_TOKEN_REUSE'
             WHERE user_id = $1 AND status = 'ACTIVE'`,
            [current.id],
          );
          await this.audit.append(client, {
            actorUserId: current.id,
            action: 'AUTH_REFRESH_REUSE_DETECTED',
            resourceType: 'SESSION',
            resourceId: current.session_id,
            scopeUnitId: current.home_unit_id ?? undefined,
            metadata: {},
          });
        }
        return null;
      }
      if (current.status === 'SUSPENDED' || current.status === 'DEACTIVATED') {
        return null;
      }

      const replacementSessionId = await this.createSession(
        client,
        current.id,
        current.device_id ?? undefined,
        ipHash,
      );
      await client.query(
        `UPDATE sessions
         SET status = 'REVOKED', revoked_at = now(), revoked_reason = 'ROTATED',
             replaced_by_session_id = $1, last_used_at = now()
         WHERE id = $2`,
        [replacementSessionId, current.session_id],
      );
      const user: AuthUserRow = current;
      const issuedTokens = await this.issueTokens(user, replacementSessionId, client);
      await this.audit.append(client, {
        actorUserId: current.id,
        action: 'AUTH_REFRESH_ROTATED',
        resourceType: 'SESSION',
        resourceId: replacementSessionId,
        scopeUnitId: current.home_unit_id ?? undefined,
        metadata: {},
      });
      return issuedTokens;
    });

    if (!tokens) {
      throw new UnauthorizedException('Refresh token is invalid.');
    }
    return tokens;
  }

  async logout(sessionId: string, userId: string): Promise<void> {
    await this.database.withActor(this.systemActor(), async (client) => {
      await client.query(
        `UPDATE sessions
         SET status = 'REVOKED', revoked_at = now(), revoked_reason = 'USER_LOGOUT'
         WHERE id = $1 AND user_id = $2 AND status = 'ACTIVE'`,
        [sessionId, userId],
      );
      const user = await this.findUserById(client, userId);
      await this.audit.append(client, {
        actorUserId: userId,
        action: 'AUTH_LOGOUT',
        resourceType: 'SESSION',
        resourceId: sessionId,
        scopeUnitId: user?.home_unit_id ?? undefined,
        metadata: {},
      });
    });
  }

  private async enforceOtpRateLimits(
    client: PoolClient,
    destinationHash: string,
    ipHash: string | null,
  ): Promise<void> {
    const lockout = await client.query<{ locked_until: Date }>(
      `SELECT locked_until FROM auth_lockouts
       WHERE destination_hash = $1 AND locked_until > now()`,
      [destinationHash],
    );
    if (lockout.rows[0]) {
      throw new HttpException(
        'OTP verification is temporarily locked. Please try again later.',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
    const perDestination = this.numberSetting('OTP_SEND_LIMIT_PER_PHONE_PER_HOUR', 3);
    const perIp = this.numberSetting('OTP_SEND_LIMIT_PER_IP_PER_HOUR', 10);
    const destinationCount = await client.query<{ count: string }>(
      `SELECT count(*)::text AS count FROM otp_challenges
       WHERE destination_hash = $1 AND created_at > now() - interval '1 hour'`,
      [destinationHash],
    );
    if (Number(destinationCount.rows[0].count) >= perDestination) {
      throw new HttpException(
        'Too many OTP requests. Please try again later.',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
    if (ipHash) {
      const ipCount = await client.query<{ count: string }>(
        `SELECT count(*)::text AS count FROM otp_challenges
         WHERE request_ip_hash = $1 AND created_at > now() - interval '1 hour'`,
        [ipHash],
      );
      if (Number(ipCount.rows[0].count) >= perIp) {
        throw new HttpException(
          'Too many OTP requests. Please try again later.',
          HttpStatus.TOO_MANY_REQUESTS,
        );
      }
    }
  }

  private async currentChallenge(
    client: PoolClient,
    destinationHash: string,
    channel: 'PHONE' | 'EMAIL',
  ): Promise<OtpChallengeRow | undefined> {
    const result = await client.query<OtpChallengeRow>(
      `SELECT id, user_id, code_hash, attempts, max_attempts
       FROM otp_challenges
       WHERE destination_hash = $1 AND channel = $2
         AND consumed_at IS NULL AND locked_at IS NULL AND expires_at > now()
       ORDER BY created_at DESC
       LIMIT 1
       FOR UPDATE`,
      [destinationHash, channel],
    );
    return result.rows[0];
  }

  private async findUserByIdentity(
    client: PoolClient,
    destination: string,
    channel: 'PHONE' | 'EMAIL',
  ): Promise<AuthUserRow | undefined> {
    const field = channel === 'PHONE' ? 'u.phone_normalized' : 'u.email_normalized';
    const result = await client.query<AuthUserRow>(
      `SELECT u.id, u.status, u.home_unit_id, h.path::text AS home_path,
              COALESCE(array_remove(array_agg(r.key), NULL), '{}') AS roles
       FROM users u
       LEFT JOIN org_units h ON h.id = u.home_unit_id
       LEFT JOIN user_roles ur ON ur.user_id = u.id
       LEFT JOIN roles r ON r.id = ur.role_id
       WHERE ${field} = $1
       GROUP BY u.id, h.path`,
      [destination],
    );
    return result.rows[0];
  }

  private async findUserById(client: PoolClient, userId: string): Promise<AuthUserRow | undefined> {
    const result = await client.query<AuthUserRow>(
      `SELECT u.id, u.status, u.home_unit_id, h.path::text AS home_path,
              COALESCE(array_remove(array_agg(r.key), NULL), '{}') AS roles
       FROM users u
       LEFT JOIN org_units h ON h.id = u.home_unit_id
       LEFT JOIN user_roles ur ON ur.user_id = u.id
       LEFT JOIN roles r ON r.id = ur.role_id
       WHERE u.id = $1
       GROUP BY u.id, h.path`,
      [userId],
    );
    return result.rows[0];
  }

  private async createSession(
    client: PoolClient,
    userId: string,
    deviceId: string | undefined,
    ipHash: string | null,
  ): Promise<string> {
    const refreshToken = randomRefreshToken();
    const refreshHash = keyedHash(refreshToken, this.requiredSecret('OTP_PEPPER'));
    const result = await client.query<{ id: string }>(
      `INSERT INTO sessions (user_id, device_id, refresh_token_hash, expires_at, ip_hash)
       VALUES ($1, $2, $3, now() + ($4 * interval '1 second'), $5)
       RETURNING id`,
      [
        userId,
        deviceId ?? null,
        refreshHash,
        this.numberSetting('JWT_REFRESH_TTL_SECONDS', 2_592_000),
        ipHash,
      ],
    );
    // Store the opaque raw token only for this transaction's caller, never in the database.
    await client.query("SELECT set_config('goye.pending_refresh_token', $1, true)", [refreshToken]);
    return result.rows[0].id;
  }

  private async issueTokens(
    user: AuthUserRow,
    sessionId: string,
    client: PoolClient,
  ): Promise<AuthTokens> {
    const tokenResult = await client.query<{ value: string }>(
      "SELECT current_setting('goye.pending_refresh_token', true) AS value",
    );
    const refreshToken = tokenResult.rows[0]?.value;
    if (!refreshToken) {
      throw new Error('Refresh token was not staged in the transaction.');
    }
    const expiresInSeconds = this.numberSetting('JWT_ACCESS_TTL_SECONDS', 900);
    const payload: AccessTokenPayload = {
      sub: user.id,
      sid: sessionId,
      roles: user.roles,
      ...(user.home_path ? { homePath: user.home_path } : {}),
    };
    const accessToken = await this.jwt.signAsync(payload, {
      secret: this.requiredSecret('JWT_ACCESS_SECRET'),
      expiresIn: expiresInSeconds,
      issuer: 'goye-api',
      audience: 'goye-client',
    });
    return {
      accessToken,
      refreshToken,
      accessTokenExpiresInSeconds: expiresInSeconds,
      refreshTokenExpiresInSeconds: this.numberSetting('JWT_REFRESH_TTL_SECONDS', 2_592_000),
    };
  }

  private systemActor(): { isSystem: true; auditSecret: string } {
    return { isSystem: true, auditSecret: this.requiredSecret('AUDIT_CHAIN_SECRET') };
  }

  private requiredSecret(name: string): string {
    const value = this.config.get<string>(name);
    if (!value || value.startsWith('replace-with-') || value.length < 32) {
      throw new ServiceUnavailableException(`${name} is not configured.`);
    }
    return value;
  }

  private numberSetting(name: string, fallback: number): number {
    const raw = this.config.get<string | number>(name);
    const value = Number(raw ?? fallback);
    if (!Number.isFinite(value) || value <= 0) {
      return fallback;
    }
    return Math.floor(value);
  }
}
