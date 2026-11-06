import { IsBoolean, IsOptional, IsString, MaxLength } from 'class-validator';

export class UpdateOrgUnitDto {
  @IsOptional()
  @IsString()
  @MaxLength(160)
  name?: string;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  code?: string;

  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}
