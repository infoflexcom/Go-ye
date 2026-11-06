import { Injectable, NotFoundException } from '@nestjs/common';
import type { AuthenticatedActor } from '../authorization/authorization.types.js';
import { DatabaseService } from '../database/database.service.js';

export interface DirectoryOrgUnit {
  id: string;
  type: string;
  name: string;
  code: string;
  parentId: string | null;
  path: string;
  isActive: boolean;
}

export interface DirectoryUser {
  id: string;
  displayName: string;
  homeUnitId: string | null;
  status: string;
}

@Injectable()
export class DirectoryService {
  constructor(private readonly database: DatabaseService) {}

  async listOrgUnits(actor: AuthenticatedActor): Promise<DirectoryOrgUnit[]> {
    return this.database.withActor(actor, async (client) => {
      const result = await client.query<{
        id: string;
        type: string;
        name: string;
        code: string;
        parent_id: string | null;
        path: string;
        is_active: boolean;
      }>(
        `SELECT id, type::text, name, code, parent_id, path::text, is_active
         FROM org_units ORDER BY path`,
      );
      return result.rows.map((row) => ({
        id: row.id,
        type: row.type,
        name: row.name,
        code: row.code,
        parentId: row.parent_id,
        path: row.path,
        isActive: row.is_active,
      }));
    });
  }

  async getOrgUnit(actor: AuthenticatedActor, id: string): Promise<DirectoryOrgUnit> {
    const units = await this.database.withActor(actor, (client) =>
      client.query<{
        id: string;
        type: string;
        name: string;
        code: string;
        parent_id: string | null;
        path: string;
        is_active: boolean;
      }>(
        `SELECT id, type::text, name, code, parent_id, path::text, is_active
         FROM org_units WHERE id = $1`,
        [id],
      ),
    );
    const row = units.rows[0];
    if (!row) {
      throw new NotFoundException('Organisation unit not found.');
    }
    return {
      id: row.id,
      type: row.type,
      name: row.name,
      code: row.code,
      parentId: row.parent_id,
      path: row.path,
      isActive: row.is_active,
    };
  }

  async getUser(actor: AuthenticatedActor, id: string): Promise<DirectoryUser> {
    const users = await this.database.withActor(actor, (client) =>
      client.query<{
        id: string;
        display_name: string;
        home_unit_id: string | null;
        status: string;
      }>('SELECT id, display_name, home_unit_id, status::text FROM users WHERE id = $1', [id]),
    );
    const row = users.rows[0];
    if (!row) {
      throw new NotFoundException('User not found.');
    }
    return {
      id: row.id,
      displayName: row.display_name,
      homeUnitId: row.home_unit_id,
      status: row.status,
    };
  }
}
