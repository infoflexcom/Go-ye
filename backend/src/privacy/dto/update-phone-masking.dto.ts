import { IsBoolean } from 'class-validator';

export class UpdatePhoneMaskingDto {
  @IsBoolean()
  maskPhoneNumbersAboveParish!: boolean;
}
