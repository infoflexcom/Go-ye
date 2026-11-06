import { IsDateString, IsIn, IsOptional } from 'class-validator';
import type { ConvertStage } from '../../converts/converts.service.js';

export class RollupFilterDto {
  @IsOptional()
  @IsDateString()
  startDate?: string;

  @IsOptional()
  @IsDateString()
  endDate?: string;

  @IsOptional()
  @IsIn(['NEW_CONVERT', 'BELIEVERS_CLASS', 'BAPTISMAL_CLASS', 'BAPTISED', 'FULLY_PLANTED'])
  stage?: ConvertStage;
}
