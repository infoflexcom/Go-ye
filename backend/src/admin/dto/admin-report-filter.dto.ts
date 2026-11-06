import { Type } from 'class-transformer';
import { IsDateString, IsIn, IsInt, IsOptional, Max, Min } from 'class-validator';
import type { ConvertStage } from '../../converts/converts.service.js';

export class AdminReportFilterDto {
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

export class AdminConvertDrillDownFilterDto extends AdminReportFilterDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  offset = 0;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit = 50;
}
