import { SetMetadata } from '@nestjs/common';

export const REQUIRED_ROLES_KEY = 'goye.requiredRoles';

export function RequireRoles(...roles: string[]) {
  return SetMetadata(REQUIRED_ROLES_KEY, roles);
}
