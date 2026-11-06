import { IsString, Matches, MaxLength } from 'class-validator';

export class ManageRoleDto {
  @IsString()
  @MaxLength(64)
  @Matches(/^[A-Z][A-Z_]{2,63}$/)
  roleKey!: string;
}
