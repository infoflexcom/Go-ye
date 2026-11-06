import { BadRequestException } from '@nestjs/common';
import {
  createHash,
  randomBytes,
  randomInt,
  scrypt as scryptCallback,
  timingSafeEqual,
} from 'node:crypto';
import { promisify } from 'node:util';
import type { OtpChannel } from './auth.types.js';

const scrypt = promisify(scryptCallback);

export interface NormalizedIdentity {
  destination: string;
  channel: OtpChannel;
}

export function normalizeIdentity(value: string): NormalizedIdentity {
  const input = value.trim();
  if (input.includes('@')) {
    const email = input.toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      throw new BadRequestException('Enter a valid email address or E.164 phone number.');
    }
    return { destination: email, channel: 'EMAIL' };
  }

  const phone = input.replace(/[\s()-]/g, '');
  if (!/^\+[1-9][0-9]{6,14}$/.test(phone)) {
    throw new BadRequestException('Enter a valid email address or E.164 phone number.');
  }
  return { destination: phone, channel: 'PHONE' };
}

export function keyedHash(value: string, pepper: string): string {
  return createHash('sha256').update(`${pepper}:${value}`).digest('hex');
}

export function randomOtp(): string {
  return randomInt(0, 1_000_000).toString().padStart(6, '0');
}

export function randomRefreshToken(): string {
  return randomBytes(48).toString('base64url');
}

export async function secretHash(value: string): Promise<string> {
  const salt = randomBytes(16).toString('hex');
  const derived = (await scrypt(value, salt, 64)) as Buffer;
  return `${salt}:${derived.toString('hex')}`;
}

export async function verifySecret(value: string, stored: string): Promise<boolean> {
  const [salt, expectedHex] = stored.split(':');
  if (!salt || !expectedHex) {
    return false;
  }
  const expected = Buffer.from(expectedHex, 'hex');
  const actual = (await scrypt(value, salt, expected.length)) as Buffer;
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}
