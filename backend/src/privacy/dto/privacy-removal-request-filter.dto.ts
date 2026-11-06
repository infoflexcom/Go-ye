import { IsIn, IsOptional } from 'class-validator';

export class PrivacyRemovalRequestFilterDto {
  @IsOptional()
  @IsIn(['PENDING', 'ANONYMISED', 'REJECTED'])
  status?: 'PENDING' | 'ANONYMISED' | 'REJECTED';
}
