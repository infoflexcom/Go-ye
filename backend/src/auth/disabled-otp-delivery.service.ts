import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import type { OtpDeliveryMessage, OtpDeliveryService } from './auth.types.js';

@Injectable()
export class DisabledOtpDeliveryService implements OtpDeliveryService {
  send(message: OtpDeliveryMessage): Promise<void> {
    void message;
    return Promise.reject(
      new ServiceUnavailableException(
        'OTP delivery is disabled until a church-owned provider is configured.',
      ),
    );
  }
}
