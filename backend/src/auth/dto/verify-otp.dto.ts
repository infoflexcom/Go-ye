import { IsIn, IsOptional, IsString, Length, MaxLength, MinLength } from 'class-validator';

export class VerifyOtpDto {
  @IsString()
  @MinLength(7)
  @MaxLength(254)
  identity!: string;

  @IsString()
  @Length(6, 6)
  code!: string;

  @IsString()
  @MinLength(8)
  @MaxLength(256)
  deviceIdentifier!: string;

  @IsIn(['ANDROID', 'IOS', 'WINDOWS', 'WEB', 'UNKNOWN'])
  platform!: 'ANDROID' | 'IOS' | 'WINDOWS' | 'WEB' | 'UNKNOWN';

  @IsOptional()
  @IsString()
  @MaxLength(120)
  deviceLabel?: string;
}
