import { Body, Controller, Get, HttpCode, Param, Patch, Post, UseGuards } from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiCreatedResponse,
  ApiOkResponse,
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import { CurrentActor } from '../authorization/current-actor.decorator.js';
import { JwtAuthGuard } from '../authorization/jwt-auth.guard.js';
import { RequireRoles } from '../authorization/roles.decorator.js';
import { RolesGuard } from '../authorization/roles.guard.js';
import type { AuthenticatedActor } from '../authorization/authorization.types.js';
import { AdminService } from './admin.service.js';
import { CreateOrgUnitDto } from './dto/create-org-unit.dto.js';
import { CreateUserDto } from './dto/create-user.dto.js';
import { ManageRoleDto } from './dto/manage-role.dto.js';
import { MoveOrgUnitDto } from './dto/move-org-unit.dto.js';
import { UpdateOrgUnitDto } from './dto/update-org-unit.dto.js';
import { UpdateUserDto } from './dto/update-user.dto.js';

@ApiTags('global administration')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, RolesGuard)
@RequireRoles('GLOBAL_ADMIN')
@Controller('admin')
export class AdminController {
  constructor(private readonly admin: AdminService) {}

  @Post('org-units')
  @ApiOperation({ summary: 'Create an organisation unit in the fixed hierarchy' })
  @ApiCreatedResponse({ description: 'Created organisation unit with generated ltree path.' })
  createOrgUnit(@CurrentActor() actor: AuthenticatedActor, @Body() dto: CreateOrgUnitDto) {
    return this.admin.createOrgUnit(actor, dto);
  }

  @Get('org-units/:id')
  @ApiOperation({ summary: 'Read a scoped organisation unit' })
  @ApiOkResponse({ description: 'Organisation unit.' })
  getOrgUnit(@CurrentActor() actor: AuthenticatedActor, @Param('id') id: string) {
    return this.admin.getOrgUnit(actor, id);
  }

  @Patch('org-units/:id')
  @ApiOperation({ summary: 'Edit or deactivate an organisation unit' })
  @ApiOkResponse({ description: 'Updated organisation unit.' })
  updateOrgUnit(
    @CurrentActor() actor: AuthenticatedActor,
    @Param('id') id: string,
    @Body() dto: UpdateOrgUnitDto,
  ) {
    return this.admin.updateOrgUnit(actor, id, dto);
  }

  @Post('org-units/:id/move')
  @ApiOperation({ summary: 'Move a unit and rebuild its complete descendant ltree path subtree' })
  @ApiOkResponse({ description: 'Audited move result.' })
  moveOrgUnit(
    @CurrentActor() actor: AuthenticatedActor,
    @Param('id') id: string,
    @Body() dto: MoveOrgUnitDto,
  ) {
    return this.admin.moveOrgUnit(actor, id, dto);
  }

  @Post('users')
  @ApiOperation({ summary: 'Create an invited user and assign roles' })
  @ApiCreatedResponse({ description: 'Created user with roles.' })
  createUser(@CurrentActor() actor: AuthenticatedActor, @Body() dto: CreateUserDto) {
    return this.admin.createUser(actor, dto);
  }

  @Patch('users/:id')
  @ApiOperation({ summary: 'Edit a user home unit or lifecycle status' })
  updateUser(
    @CurrentActor() actor: AuthenticatedActor,
    @Param('id') id: string,
    @Body() dto: UpdateUserDto,
  ) {
    return this.admin.updateUser(actor, id, dto);
  }

  @Post('users/:id/roles')
  @ApiOperation({ summary: 'Assign a system role to a user' })
  addRole(
    @CurrentActor() actor: AuthenticatedActor,
    @Param('id') id: string,
    @Body() dto: ManageRoleDto,
  ) {
    return this.admin.addRole(actor, id, dto.roleKey);
  }

  @Post('users/:id/roles/:roleKey/revoke')
  @HttpCode(200)
  @ApiOperation({ summary: 'Revoke a system role from a user' })
  removeRole(
    @CurrentActor() actor: AuthenticatedActor,
    @Param('id') id: string,
    @Param('roleKey') roleKey: string,
  ) {
    return this.admin.removeRole(actor, id, roleKey);
  }
}
