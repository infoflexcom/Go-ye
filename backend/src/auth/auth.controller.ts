import { Body, Controller, HttpCode, HttpStatus, Ip, Post } from '@nestjs/common';
import { ApiAcceptedResponse, ApiOkResponse, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AuthService } from './auth.service.js';
import { RefreshTokenDto } from './dto/refresh-token.dto.js';
import { RequestOtpDto } from './dto/request-otp.dto.js';
import { VerifyOtpDto } from './dto/verify-otp.dto.js';

@ApiTags('authentication')
@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post('otp/request')
  @HttpCode(HttpStatus.ACCEPTED)
  @ApiOperation({ summary: 'Request a one-time passcode for an approved identity' })
  @ApiAcceptedResponse({
    description: 'Generic response that does not disclose account existence.',
  })
  requestOtp(@Body() dto: RequestOtpDto, @Ip() ipAddress: string): Promise<{ accepted: true }> {
    return this.auth.requestOtp(dto, ipAddress);
  }

  @Post('otp/verify')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Verify OTP and start a device-bound session' })
  @ApiOkResponse({ description: 'Short-lived access JWT and rotated opaque refresh token.' })
  verifyOtp(@Body() dto: VerifyOtpDto, @Ip() ipAddress: string) {
    return this.auth.verifyOtp(dto, ipAddress);
  }

  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Rotate an opaque refresh token' })
  @ApiOkResponse({ description: 'New access JWT and new refresh token.' })
  refresh(@Body() dto: RefreshTokenDto, @Ip() ipAddress: string) {
    return this.auth.refresh(dto, ipAddress);
  }
}
