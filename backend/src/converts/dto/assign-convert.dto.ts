import { IsUUID } from 'class-validator';

export class AssignConvertDto {
  @IsUUID()
  parishId!: string;
}
