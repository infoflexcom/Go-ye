import { IsIn, IsOptional, IsString, MaxLength } from 'class-validator';

export class AdvanceConvertStageDto {
  @IsIn(['BELIEVERS_CLASS', 'BAPTISMAL_CLASS', 'BAPTISED', 'FULLY_PLANTED'])
  stage!: 'BELIEVERS_CLASS' | 'BAPTISMAL_CLASS' | 'BAPTISED' | 'FULLY_PLANTED';

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  note?: string;
}
