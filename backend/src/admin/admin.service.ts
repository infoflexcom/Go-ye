import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { PoolClient } from 'pg';
import { AuditService } from '../audit/audit.service.js';
import type { AuthenticatedActor } from '../authorization/authorization.types.js';
import { DatabaseService, type DatabaseActor } from '../database/database.service.js';
import { normalizeIdentity } from '../auth/auth.identity.js';
import type { CreateOrgUnitDto } from './dto/create-org-unit.dto.js';
import type { CreateUserDto } from './dto/create-user.dto.js';
import type { MoveOrgUnitDto } from './dto/move-org-unit.dto.js';
import type { UpdateOrgUnitDto } from './dto/update-org-unit.dto.js';
import type { UpdateUserDto } from './dto/update-user.dto.js';

export interface OrgUnitRow {
  id: string;
  type: string;
  name: string;
  code: string;
  parent_id: string | null;
  path: string;
  is_active: boolean;
}

export interface UserRow {
  id: string;
  display_name: string;
  home_unit_id: string | null;
  status: string;
  roles: string[];
}

@Injectable()
export class AdminService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly config: ConfigService,
  ) {}

  async createOrgUnit(actor: AuthenticatedActor, dto: CreateOrgUnitDto): Promise<OrgUnitRow> {
    return this.withGlobalAdmin(actor, async (client) => {
      const created = await client.query<OrgUnitRow>(
        `INSERT INTO org_units (type, name, code, parent_id)
         VALUES ($1::org_unit_type, $2, $3, $4)
         RETURNING id, type::text, name, code, parent_id, path::text, is_active`,
        [dto.type, dto.name.trim(), dto.code.trim().toUpperCase(), dto.parentId ?? null],
      );
      const unit = created.rows[0];
      await this.audit.append(client, {
        actorUserId: actor.id,
        action: 'ORG_UNIT_CREATED',
        resourceType: 'ORG_UNIT',
        resourceId: unit.id,
        scopeUnitId: unit.id,
        metadata: { type: unit.type, code: unit.code, parentId: unit.parent_id },
      });
      return unit;
    });
  }

  async getOrgUnit(actor: AuthenticatedActor, id: string): Promise<OrgUnitRow> {
    return this.database.withActor(this.databaseActor(actor), async (client) => {
      const result = await client.query<OrgUnitRow>(
        `SELECT id, type::text, name, code, parent_id, path::text, is_active
         FROM org_units WHERE id = $1`,
        [id],
      );
      if (!result.rows[0]) {
        throw new NotFoundException('Organisation unit not found.');
      }
      return result.rows[0];
    });
  }

  async updateOrgUnit(
    actor: AuthenticatedActor,
    id: string,
    dto: UpdateOrgUnitDto,
  ): Promise<OrgUnitRow> {
    return this.withGlobalAdmin(actor, async (client) => {
      const existing = await this.getOrgUnitForUpdate(client, id);
      if (dto.isActive === false) {
        const activeDescendants = await client.query<{ exists: boolean }>(
          `SELECT EXISTS(
            SELECT 1 FROM org_units WHERE path <@ $1::ltree AND id <> $2 AND is_active
          ) AS exists`,
          [existing.path, id],
        );
        if (activeDescendants.rows[0].exists) {
          throw new BadRequestException('Deactivate child units before deactivating this unit.');
        }
      }
      if (dto.isActive === true && existing.parent_id) {
        const parent = await client.query<{ is_active: boolean }>(
          'SELECT is_active FROM org_units WHERE id = $1',
          [existing.parent_id],
        );
        if (!parent.rows[0]?.is_active) {
          throw new BadRequestException('Cannot activate a unit under an inactive parent.');
        }
      }

      const updated = await client.query<OrgUnitRow>(
        `UPDATE org_units
         SET name = COALESCE($1, name),
             code = COALESCE($2, code),
             is_active = COALESCE($3, is_active)
         WHERE id = $4
         RETURNING id, type::text, name, code, parent_id, path::text, is_active`,
        [
          dto.name?.trim() ?? null,
          dto.code?.trim().toUpperCase() ?? null,
          dto.isActive ?? null,
          id,
        ],
      );
      const unit = updated.rows[0];
      await this.audit.append(client, {
        actorUserId: actor.id,
        action: unit.is_active ? 'ORG_UNIT_UPDATED' : 'ORG_UNIT_DEACTIVATED',
        resourceType: 'ORG_UNIT',
        resourceId: unit.id,
        scopeUnitId: unit.id,
        metadata: { code: unit.code, isActive: unit.is_active },
      });
      return unit;
    });
  }

  async moveOrgUnit(
    actor: AuthenticatedActor,
    id: string,
    dto: MoveOrgUnitDto,
  ): Promise<{ unitId: string; oldPath: string; newPath: string; movedDescendantCount: number }> {
    return this.withGlobalAdmin(actor, async (client) => {
      const result = await client.query<{
        unit_id: string;
        old_path: string;
        new_path: string;
        moved_descendant_count: number;
      }>('SELECT * FROM goye_move_org_unit($1, $2)', [id, dto.newParentId]);
      const move = result.rows[0];
      if (!move) {
        throw new NotFoundException('Organisation unit not found.');
      }
      await this.audit.append(client, {
        actorUserId: actor.id,
        action: 'ORG_UNIT_MOVED',
        resourceType: 'ORG_UNIT',
        resourceId: move.unit_id,
        scopeUnitId: move.unit_id,
        metadata: {
          oldPath: move.old_path,
          newPath: move.new_path,
          movedDescendantCount: move.moved_descendant_count,
          newParentId: dto.newParentId,
        },
      });
      return {
        unitId: move.unit_id,
        oldPath: move.old_path,
        newPath: move.new_path,
        movedDescendantCount: move.moved_descendant_count,
      };
    });
  }

  async createUser(actor: AuthenticatedActor, dto: CreateUserDto): Promise<UserRow> {
    return this.withGlobalAdmin(actor, async (client) => {
      const phone = dto.phone ? normalizeIdentity(dto.phone) : undefined;
      const email = dto.email ? normalizeIdentity(dto.email) : undefined;
      if (phone?.channel === 'EMAIL' || email?.channel === 'PHONE') {
        throw new BadRequestException('Phone and email values are not in the expected format.');
      }
      if (!phone && !email) {
        throw new BadRequestException('A phone number or email address is required.');
      }
      const roleKeys = [...new Set(dto.roles)];
      await this.assertRoleAndHomeUnitRules(client, roleKeys, dto.homeUnitId);

      const inserted = await client.query<{ id: string }>(
        `INSERT INTO users (display_name, phone_normalized, email_normalized, home_unit_id, status)
         VALUES ($1, $2, $3, $4, 'INVITED') RETURNING id`,
        [
          dto.displayName.trim(),
          phone?.destination ?? null,
          email?.destination ?? null,
          dto.homeUnitId ?? null,
        ],
      );
      await this.assignRoles(client, inserted.rows[0].id, roleKeys, actor.id);
      const user = await this.getUserForAdmin(client, inserted.rows[0].id);
      await this.audit.append(client, {
        actorUserId: actor.id,
        action: 'USER_CREATED',
        resourceType: 'USER',
        resourceId: user.id,
        scopeUnitId: user.home_unit_id ?? undefined,
        metadata: { roles: user.roles },
      });
      return user;
    });
  }

  async updateUser(actor: AuthenticatedActor, id: string, dto: UpdateUserDto): Promise<UserRow> {
    return this.withGlobalAdmin(actor, async (client) => {
      const existing = await this.getUserForAdmin(client, id);
      if (dto.homeUnitId !== undefined) {
        await this.assertRoleAndHomeUnitRules(client, existing.roles, dto.homeUnitId ?? undefined);
      }
      const updated = await client.query<{ id: string }>(
        `UPDATE users
         SET display_name = COALESCE($1, display_name),
             home_unit_id = CASE WHEN $2::boolean THEN $3::uuid ELSE home_unit_id END,
             status = COALESCE($4::user_status, status),
             deactivated_at = CASE
               WHEN COALESCE($4::user_status, status) = 'DEACTIVATED' THEN now()
               WHEN COALESCE($4::user_status, status) <> 'DEACTIVATED' THEN NULL
               ELSE deactivated_at END,
             updated_at = now()
         WHERE id = $5
         RETURNING id`,
        [
          dto.displayName?.trim() ?? null,
          dto.homeUnitId !== undefined,
          dto.homeUnitId ?? null,
          dto.status ?? null,
          id,
        ],
      );
      if (!updated.rows[0]) {
        throw new NotFoundException('User not found.');
      }
      const user = await this.getUserForAdmin(client, id);
      await this.audit.append(client, {
        actorUserId: actor.id,
        action: 'USER_UPDATED',
        resourceType: 'USER',
        resourceId: user.id,
        scopeUnitId: user.home_unit_id ?? undefined,
        metadata: { status: user.status },
      });
      return user;
    });
  }

  async addRole(actor: AuthenticatedActor, userId: string, roleKey: string): Promise<UserRow> {
    return this.withGlobalAdmin(actor, async (client) => {
      const user = await this.getUserForAdmin(client, userId);
      const roles = [...new Set([...user.roles, roleKey])];
      await this.assertRoleAndHomeUnitRules(client, roles, user.home_unit_id ?? undefined);
      await this.assignRoles(client, userId, [roleKey], actor.id);
      const updated = await this.getUserForAdmin(client, userId);
      await this.audit.append(client, {
        actorUserId: actor.id,
        action: 'USER_ROLE_ASSIGNED',
        resourceType: 'USER',
        resourceId: userId,
        scopeUnitId: updated.home_unit_id ?? undefined,
        metadata: { roleKey },
      });
      return updated;
    });
  }

  async removeRole(actor: AuthenticatedActor, userId: string, roleKey: string): Promise<UserRow> {
    return this.withGlobalAdmin(actor, async (client) => {
      const user = await this.getUserForAdmin(client, userId);
      const remainingRoles = user.roles.filter((key) => key !== roleKey);
      await this.assertRoleAndHomeUnitRules(client, remainingRoles, user.home_unit_id ?? undefined);
      await client.query(
        `DELETE FROM user_roles ur
         USING roles r
         WHERE ur.role_id = r.id AND ur.user_id = $1 AND r.key = $2`,
        [userId, roleKey],
      );
      const updated = await this.getUserForAdmin(client, userId);
      await this.audit.append(client, {
        actorUserId: actor.id,
        action: 'USER_ROLE_REVOKED',
        resourceType: 'USER',
        resourceId: userId,
        scopeUnitId: updated.home_unit_id ?? undefined,
        metadata: { roleKey },
      });
      return updated;
    });
  }

  private async withGlobalAdmin<T>(
    actor: AuthenticatedActor,
    callback: (client: PoolClient) => Promise<T>,
  ): Promise<T> {
    if (!actor.isGlobalAdmin) {
      throw new ForbiddenException('Global Admin permission is required.');
    }
    return this.database.withActor(this.databaseActor(actor), callback);
  }

  private databaseActor(actor: AuthenticatedActor): DatabaseActor {
    const secret = this.config.get<string>('AUDIT_CHAIN_SECRET');
    if (!secret || secret.startsWith('replace-with-') || secret.length < 32) {
      throw new BadRequestException('Audit chain is not configured.');
    }
    return {
      userId: actor.id,
      homePath: actor.homePath,
      isGlobalAdmin: actor.isGlobalAdmin,
      auditSecret: secret,
    };
  }

  private async getOrgUnitForUpdate(client: PoolClient, id: string): Promise<OrgUnitRow> {
    const result = await client.query<OrgUnitRow>(
      `SELECT id, type::text, name, code, parent_id, path::text, is_active
       FROM org_units WHERE id = $1 FOR UPDATE`,
      [id],
    );
    if (!result.rows[0]) {
      throw new NotFoundException('Organisation unit not found.');
    }
    return result.rows[0];
  }

  private async getUserForAdmin(client: PoolClient, userId: string): Promise<UserRow> {
    const result = await client.query<UserRow>(
      `SELECT u.id, u.display_name, u.home_unit_id, u.status,
              COALESCE(array_agg(r.key ORDER BY r.key) FILTER (WHERE r.key IS NOT NULL), ARRAY[]::text[]) AS roles
       FROM users u
       LEFT JOIN user_roles ur ON ur.user_id = u.id
       LEFT JOIN roles r ON r.id = ur.role_id
       WHERE u.id = $1
       GROUP BY u.id`,
      [userId],
    );
    if (!result.rows[0]) {
      throw new NotFoundException('User not found.');
    }
    return result.rows[0];
  }

  private async assertRoleAndHomeUnitRules(
    client: PoolClient,
    roleKeys: string[],
    homeUnitId?: string,
  ): Promise<void> {
    if (roleKeys.length === 0) {
      throw new BadRequestException('Every user must have at least one role.');
    }
    const roles = await client.query<{ key: string }>(
      'SELECT key FROM roles WHERE key = ANY($1::text[])',
      [roleKeys],
    );
    if (roles.rows.length !== roleKeys.length) {
      throw new BadRequestException('One or more roles do not exist.');
    }
    const globalAdmin = roleKeys.includes('GLOBAL_ADMIN');
    if (globalAdmin && homeUnitId) {
      throw new BadRequestException('A Global Admin must not have a home unit.');
    }
    if (!globalAdmin && !homeUnitId) {
      throw new BadRequestException('Every non-Global-Admin user needs one home unit.');
    }
    if (homeUnitId) {
      const unit = await client.query<{ is_active: boolean }>(
        'SELECT is_active FROM org_units WHERE id = $1',
        [homeUnitId],
      );
      if (!unit.rows[0]) {
        throw new NotFoundException('Home organisation unit not found.');
      }
      if (!unit.rows[0].is_active) {
        throw new BadRequestException('A user cannot be assigned to an inactive home unit.');
      }
    }
  }

  private async assignRoles(
    client: PoolClient,
    userId: string,
    roleKeys: string[],
    assignedBy: string,
  ): Promise<void> {
    if (roleKeys.length === 0) {
      return;
    }
    await client.query(
      `INSERT INTO user_roles (user_id, role_id, assigned_by)
       SELECT $1, id, $3 FROM roles WHERE key = ANY($2::text[])
       ON CONFLICT (user_id, role_id) DO NOTHING`,
      [userId, roleKeys, assignedBy],
    );
  }
}
