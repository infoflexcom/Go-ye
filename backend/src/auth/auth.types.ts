export type OtpChannel = 'PHONE' | 'EMAIL';

export interface OtpDeliveryMessage {
  destination: string;
  channel: OtpChannel;
  code: string;
  expiresInSeconds: number;
}

export interface OtpDeliveryService {
  send(message: OtpDeliveryMessage): Promise<void>;
}

export const OTP_DELIVERY_SERVICE = Symbol('OTP_DELIVERY_SERVICE');

export interface AccessTokenPayload {
  sub: string;
  sid: string;
  roles: string[];
  homePath?: string;
}

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
  accessTokenExpiresInSeconds: number;
  refreshTokenExpiresInSeconds: number;
}
