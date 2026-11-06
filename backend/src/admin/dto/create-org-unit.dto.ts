import { IsEnum, IsNotEmpty, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';

export const orgUnitTypes = ['COUNTRY', 'REGION', 'PROVINCE', 'ZONE', 'AREA', 'PARISH'] as const;
export type OrgUnitType = (typeof orgUnitTypes)[number];

export class CreateOrgUnitDto {
  @IsEnum(orgUnitTypes)
  type!: OrgUnitType;

  @IsString()
  @IsNotEmpty()
  @MaxLength(160)
  name!: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(64)
  code!: string;

  @IsOptional()
  @IsUUID()
  parentId?: string;
}
