import { IsString, MaxLength } from 'class-validator';

export class AddConvertActivityDto {
  @IsString()
  @MaxLength(1000)
  note!: string;
}
