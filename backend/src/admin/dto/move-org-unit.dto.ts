import { IsUUID } from 'class-validator';

export class MoveOrgUnitDto {
  @IsUUID()
  newParentId!: string;
}
