import { IsIn, IsOptional, IsString, MaxLength } from 'class-validator';

export class ResolveConvertRemovalDto {
  @IsIn(['ANONYMISE', 'REJECT'])
  outcome!: 'ANONYMISE' | 'REJECT';

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  note?: string;
}
