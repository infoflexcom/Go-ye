import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import type { Request } from 'express';
import { AuthService } from '../auth/auth.service.js';
import type { AuthenticatedActor } from './authorization.types.js';

interface AuthenticatedRequest extends Request {
  user?: AuthenticatedActor;
}

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(private readonly auth: AuthService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const header = request.headers.authorization;
    if (!header?.startsWith('Bearer ')) {
      throw new UnauthorizedException('A bearer access token is required.');
    }
    request.user = await this.auth.authenticateAccessToken(header.slice('Bearer '.length));
    return true;
  }
}
