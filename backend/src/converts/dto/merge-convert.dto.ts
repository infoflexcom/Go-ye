import { IsUUID } from 'class-validator';

export class MergeConvertDto {
  @IsUUID()
  duplicateConvertId!: string;
}
