import { IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

export class RequestOtpDto {
  @IsString()
  @MinLength(7)
  @MaxLength(254)
  identity!: string;

  @IsOptional()
  @IsString()
  @MaxLength(256)
  deviceIdentifier?: string;
}
