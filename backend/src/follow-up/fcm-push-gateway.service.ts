import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createSign } from 'node:crypto';

interface FirebaseServiceAccount {
  client_email: string;
  private_key: string;
  project_id?: string;
  token_uri?: string;
}

interface CachedAccessToken {
  accessToken: string;
  expiresAt: number;
}

export class FcmPushError extends Error {
  constructor(
    readonly code: 'FCM_CONFIGURATION_ERROR' | 'FCM_TOKEN_INVALID' | 'FCM_TRANSIENT_FAILURE',
  ) {
    super(code);
  }
}

@Injectable()
export class FcmPushGatewayService {
  private cachedToken?: CachedAccessToken;

  constructor(private readonly config: ConfigService) {}

  isConfigured(): boolean {
    return (
      this.config.get<boolean>('FCM_ENABLED', false) &&
      Boolean(this.config.get<string>('FIREBASE_SERVICE_ACCOUNT_JSON')) &&
      Boolean(this.projectId())
    );
  }

  async sendDueReminder(input: {
    token: string;
    reminderJobId: string;
    followUpTaskId: string;
    idempotencyKey: string;
  }): Promise<void> {
    if (!this.isConfigured()) {
      throw new FcmPushError('FCM_CONFIGURATION_ERROR');
    }
    const accessToken = await this.accessToken();
    const projectId = this.projectId();
    if (!projectId) {
      throw new FcmPushError('FCM_CONFIGURATION_ERROR');
    }
    let response: Response;
    try {
      response = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
        method: 'POST',
        headers: {
          authorization: `Bearer ${accessToken}`,
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token: input.token,
            notification: {
              title: 'Follow-up due',
              body: 'Open Go-Ye to record the outcome.',
            },
            data: {
              reminderJobId: input.reminderJobId,
              followUpTaskId: input.followUpTaskId,
              idempotencyKey: input.idempotencyKey,
            },
            android: {
              priority: 'high',
              notification: {
                channel_id: 'goye_follow_up',
                tag: input.idempotencyKey,
              },
            },
          },
        }),
      });
    } catch {
      throw new FcmPushError('FCM_TRANSIENT_FAILURE');
    }
    if (response.ok) {
      return;
    }

    const responseText = await response.text();
    if (
      response.status === 404 ||
      responseText.includes('UNREGISTERED') ||
      responseText.includes('INVALID_ARGUMENT')
    ) {
      throw new FcmPushError('FCM_TOKEN_INVALID');
    }
    if (response.status >= 500 || response.status === 429) {
      throw new FcmPushError('FCM_TRANSIENT_FAILURE');
    }
    throw new FcmPushError('FCM_CONFIGURATION_ERROR');
  }

  private async accessToken(): Promise<string> {
    const now = Date.now();
    if (this.cachedToken && this.cachedToken.expiresAt > now + 60_000) {
      return this.cachedToken.accessToken;
    }
    const serviceAccount = this.serviceAccount();
    const issuedAt = Math.floor(now / 1000);
    const assertion = this.signServiceAccountJwt(serviceAccount, issuedAt);
    let response: Response;
    try {
      response = await fetch(serviceAccount.token_uri ?? 'https://oauth2.googleapis.com/token', {
        method: 'POST',
        headers: { 'content-type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
          grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          assertion,
        }),
      });
    } catch {
      throw new FcmPushError('FCM_TRANSIENT_FAILURE');
    }
    if (!response.ok) {
      throw new FcmPushError(
        response.status >= 500 ? 'FCM_TRANSIENT_FAILURE' : 'FCM_CONFIGURATION_ERROR',
      );
    }
    const payload = (await response.json()) as { access_token?: unknown; expires_in?: unknown };
    if (typeof payload.access_token !== 'string' || typeof payload.expires_in !== 'number') {
      throw new FcmPushError('FCM_CONFIGURATION_ERROR');
    }
    this.cachedToken = {
      accessToken: payload.access_token,
      expiresAt: now + payload.expires_in * 1000,
    };
    return payload.access_token;
  }

  private serviceAccount(): FirebaseServiceAccount {
    const raw = this.config.get<string>('FIREBASE_SERVICE_ACCOUNT_JSON');
    if (!raw) {
      throw new FcmPushError('FCM_CONFIGURATION_ERROR');
    }
    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch {
      throw new FcmPushError('FCM_CONFIGURATION_ERROR');
    }
    if (
      !parsed ||
      typeof parsed !== 'object' ||
      !('client_email' in parsed) ||
      !('private_key' in parsed) ||
      typeof parsed.client_email !== 'string' ||
      typeof parsed.private_key !== 'string'
    ) {
      throw new FcmPushError('FCM_CONFIGURATION_ERROR');
    }
    const serviceAccount = parsed as Record<string, unknown>;
    const projectId = serviceAccount['project_id'];
    const tokenUri = serviceAccount['token_uri'];
    return {
      client_email: serviceAccount['client_email'] as string,
      private_key: serviceAccount['private_key'] as string,
      ...(typeof projectId === 'string' ? { project_id: projectId } : {}),
      ...(typeof tokenUri === 'string' ? { token_uri: tokenUri } : {}),
    };
  }

  private projectId(): string | undefined {
    const configured = this.config.get<string>('FIREBASE_PROJECT_ID');
    if (configured) {
      return configured;
    }
    const raw = this.config.get<string>('FIREBASE_SERVICE_ACCOUNT_JSON');
    if (!raw) {
      return undefined;
    }
    try {
      const parsed = JSON.parse(raw) as { project_id?: unknown };
      return typeof parsed.project_id === 'string' && parsed.project_id
        ? parsed.project_id
        : undefined;
    } catch {
      return undefined;
    }
  }

  private signServiceAccountJwt(serviceAccount: FirebaseServiceAccount, issuedAt: number): string {
    const header = this.base64Url({ alg: 'RS256', typ: 'JWT' });
    const claims = this.base64Url({
      iss: serviceAccount.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: serviceAccount.token_uri ?? 'https://oauth2.googleapis.com/token',
      iat: issuedAt,
      exp: issuedAt + 3600,
    });
    const signer = createSign('RSA-SHA256');
    signer.update(`${header}.${claims}`);
    signer.end();
    return `${header}.${claims}.${signer.sign(serviceAccount.private_key, 'base64url')}`;
  }

  private base64Url(value: Record<string, unknown>): string {
    return Buffer.from(JSON.stringify(value)).toString('base64url');
  }
}
