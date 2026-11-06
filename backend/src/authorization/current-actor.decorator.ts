import { createParamDecorator, type ExecutionContext } from '@nestjs/common';
import type { Request } from 'express';
import type { AuthenticatedActor } from './authorization.types.js';

interface AuthenticatedRequest extends Request {
  user?: AuthenticatedActor;
}

export const CurrentActor = createParamDecorator(
  (_: unknown, context: ExecutionContext): AuthenticatedActor => {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    if (!request.user) {
      throw new Error('Authenticated actor was not attached to the request.');
    }
    return request.user;
  },
);
