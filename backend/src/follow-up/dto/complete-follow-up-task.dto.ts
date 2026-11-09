import { IsIn, IsOptional, IsString, MaxLength } from 'class-validator';

const followUpOutcomes = ['COMPLETED', 'NO_CONTACT', 'RESCHEDULED', 'DECLINED', 'OTHER'] as const;

export type FollowUpTaskOutcome = (typeof followUpOutcomes)[number];

export class CompleteFollowUpTaskDto {
  @IsOptional()
  @IsIn(followUpOutcomes)
  outcome?: FollowUpTaskOutcome;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  note?: string;
}
