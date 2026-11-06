import { IsOptional, IsString, MaxLength } from 'class-validator';

export class RequestConvertRemovalDto {
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  reason?: string;
}
