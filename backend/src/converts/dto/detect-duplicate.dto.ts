import { IsString, MaxLength } from 'class-validator';

export class DetectDuplicateDto {
  @IsString()
  @MaxLength(32)
  phone!: string;
}
