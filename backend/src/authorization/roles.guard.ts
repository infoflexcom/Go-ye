import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { Request } from 'express';
import { REQUIRED_ROLES_KEY } from './roles.decorator.js';
import type { AuthenticatedActor } from './authorization.types.js';

interface AuthenticatedRequest extends Request {
  user?: AuthenticatedActor;
}

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const required = this.reflector.getAllAndOverride<string[]>(REQUIRED_ROLES_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (!required || required.length === 0) {
      return true;
    }
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const actor = request.user;
    if (!actor || !required.some((role) => actor.roles.includes(role))) {
      throw new ForbiddenException('You do not have the required role.');
    }
    return true;
  }
}
