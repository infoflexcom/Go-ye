import { IsBoolean, IsInt, IsOptional, Max, Min } from 'class-validator';

export class UpdateFollowUpCadenceStepDto {
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(8760)
  dueOffsetHours?: number;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(365)
  recurrenceDays?: number;

  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}
