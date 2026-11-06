import { Injectable, InternalServerErrorException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';

const encryptionVersion = 1;
const ivLength = 12;
const tagLength = 16;

@Injectable()
export class FieldEncryptionService {
  private key?: Buffer;

  constructor(private readonly config: ConfigService) {}

  encrypt(value: string): Buffer {
    const iv = randomBytes(ivLength);
    const cipher = createCipheriv('aes-256-gcm', this.encryptionKey(), iv);
    const ciphertext = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
    const tag = cipher.getAuthTag();
    return Buffer.concat([Buffer.from([encryptionVersion]), iv, tag, ciphertext]);
  }

  decrypt(value: Buffer): string {
    if (value.length <= 1 + ivLength + tagLength || value[0] !== encryptionVersion) {
      throw new InternalServerErrorException(
        'Stored encrypted convert data has an invalid format.',
      );
    }
    const iv = value.subarray(1, 1 + ivLength);
    const tag = value.subarray(1 + ivLength, 1 + ivLength + tagLength);
    const ciphertext = value.subarray(1 + ivLength + tagLength);
    try {
      const decipher = createDecipheriv('aes-256-gcm', this.encryptionKey(), iv);
      decipher.setAuthTag(tag);
      return Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString('utf8');
    } catch {
      throw new InternalServerErrorException('Stored encrypted convert data cannot be decrypted.');
    }
  }

  private encryptionKey(): Buffer {
    if (this.key) {
      return this.key;
    }
    const encoded = this.config.get<string>('PII_ENCRYPTION_KEY');
    if (!encoded || encoded.startsWith('replace-with-')) {
      throw new InternalServerErrorException(
        'PII_ENCRYPTION_KEY must be configured before storing converts.',
      );
    }
    const key = Buffer.from(encoded, 'base64');
    if (key.length !== 32) {
      throw new InternalServerErrorException('PII_ENCRYPTION_KEY must decode to exactly 32 bytes.');
    }
    this.key = key;
    return key;
  }
}
