import { Type } from 'class-transformer';
import {
  Equals,
  IsBoolean,
  IsIn,
  IsNotEmpty,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  ValidateNested,
} from 'class-validator';

class ConsentDto {
  @IsBoolean()
  @Equals(true, { message: 'Consent must be affirmatively granted before a convert can be saved.' })
  granted!: boolean;

  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  version!: string;

  @IsIn(['VERBAL', 'DIGITAL', 'WRITTEN'])
  method!: 'VERBAL' | 'DIGITAL' | 'WRITTEN';
}

export class CreateConvertDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(160)
  fullName!: string;

  @IsOptional()
  @IsString()
  @MaxLength(32)
  phone?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  address?: string;

  @IsOptional()
  @IsUUID()
  registeredAtUnitId?: string;

  @ValidateNested()
  @Type(() => ConsentDto)
  consent!: ConsentDto;
}
