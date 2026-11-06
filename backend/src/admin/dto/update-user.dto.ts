import { IsIn, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';

export class UpdateUserDto {
  @IsOptional()
  @IsString()
  @MaxLength(160)
  displayName?: string;

  @IsOptional()
  @IsUUID()
  homeUnitId?: string | null;

  @IsOptional()
  @IsIn(['ACTIVE', 'INVITED', 'SUSPENDED', 'DEACTIVATED'])
  status?: 'ACTIVE' | 'INVITED' | 'SUSPENDED' | 'DEACTIVATED';
}
