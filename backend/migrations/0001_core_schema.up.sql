-- Phase 1 core identity and hierarchy schema.
-- Rollback: run 0001_core_schema.down.sql only when no later migration depends on these tables.

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS ltree;

CREATE TYPE org_unit_type AS ENUM ('COUNTRY', 'REGION', 'PROVINCE', 'ZONE', 'AREA', 'PARISH');
CREATE TYPE user_status AS ENUM ('ACTIVE', 'INVITED', 'SUSPENDED', 'DEACTIVATED');
CREATE TYPE device_platform AS ENUM ('ANDROID', 'IOS', 'WINDOWS', 'WEB', 'UNKNOWN');
CREATE TYPE session_status AS ENUM ('ACTIVE', 'REVOKED', 'EXPIRED');

CREATE TABLE roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key text NOT NULL UNIQUE,
  name text NOT NULL,
  description text NOT NULL,
  is_system boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT roles_key_format CHECK (key ~ '^[A-Z][A-Z_]{2,63}$')
);

INSERT INTO roles (key, name, description) VALUES
  ('GLOBAL_ADMIN', 'Global Admin', 'Global RCCG administration and cross-country oversight.'),
  ('COUNTRY_ADMIN', 'Country Admin', 'Country-level operational administration.'),
  ('REGION_LEADER', 'Region Leader', 'Region-level leadership.'),
  ('PROVINCE_LEADER', 'Province Leader', 'Province-level leadership.'),
  ('ZONE_LEADER', 'Zone Leader', 'Zone-level leadership.'),
  ('AREA_LEADER', 'Area Leader', 'Area-level leadership.'),
  ('PARISH_PASTOR', 'Parish Pastor', 'Parish oversight and worker access administration.'),
  ('SOUL_WINNER', 'Soul Winner', 'Registers and follows assigned converts.'),
  ('FOLLOW_UP_WORKER', 'Follow-up Worker', 'Completes assigned follow-up tasks.'),
  ('CONTENT_ADMIN', 'Content Admin', 'Manages tract content without convert-data access.'),
  ('PRIVACY_OFFICER', 'Privacy Officer', 'Processes authorised privacy requests.')
ON CONFLICT (key) DO NOTHING;

CREATE TABLE org_units (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type org_unit_type NOT NULL,
  name text NOT NULL,
  code text NOT NULL,
  parent_id uuid REFERENCES org_units(id) ON DELETE RESTRICT,
  path ltree NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deactivated_at timestamptz,
  CONSTRAINT org_units_name_not_blank CHECK (length(btrim(name)) > 0),
  CONSTRAINT org_units_code_not_blank CHECK (length(btrim(code)) > 0),
  CONSTRAINT org_units_code_unique UNIQUE (code),
  CONSTRAINT org_units_deactivation_consistent CHECK (
    (is_active AND deactivated_at IS NULL) OR (NOT is_active AND deactivated_at IS NOT NULL)
  )
);
CREATE INDEX org_units_path_gist_idx ON org_units USING GIST (path);
CREATE INDEX org_units_parent_id_idx ON org_units (parent_id);
CREATE INDEX org_units_active_path_idx ON org_units (is_active, path);

CREATE OR REPLACE FUNCTION goye_unit_label(p_id uuid)
RETURNS ltree
LANGUAGE sql
IMMUTABLE
STRICT
AS $$
  SELECT ('u' || replace(p_id::text, '-', ''))::ltree;
$$;

CREATE OR REPLACE FUNCTION goye_expected_parent_type(p_type org_unit_type)
RETURNS org_unit_type
LANGUAGE sql
IMMUTABLE
STRICT
AS $$
  SELECT CASE p_type
    WHEN 'REGION' THEN 'COUNTRY'::org_unit_type
    WHEN 'PROVINCE' THEN 'REGION'::org_unit_type
    WHEN 'ZONE' THEN 'PROVINCE'::org_unit_type
    WHEN 'AREA' THEN 'ZONE'::org_unit_type
    WHEN 'PARISH' THEN 'AREA'::org_unit_type
    ELSE NULL
  END;
$$;

CREATE OR REPLACE FUNCTION goye_prepare_org_unit()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  parent_type org_unit_type;
  parent_path ltree;
  parent_active boolean;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.type <> OLD.type THEN
      RAISE EXCEPTION 'org unit type is immutable' USING ERRCODE = '22023';
    END IF;
    IF NEW.parent_id IS DISTINCT FROM OLD.parent_id THEN
      RAISE EXCEPTION 'use move_org_unit to change a parent' USING ERRCODE = '22023';
    END IF;
    IF NEW.path <> OLD.path THEN
      RAISE EXCEPTION 'org unit path is managed by the database' USING ERRCODE = '22023';
    END IF;
    NEW.updated_at := now();
    IF NEW.is_active AND NOT OLD.is_active THEN
      NEW.deactivated_at := NULL;
    ELSIF NOT NEW.is_active AND OLD.is_active THEN
      NEW.deactivated_at := now();
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.parent_id IS NULL THEN
    IF NEW.type <> 'COUNTRY' THEN
      RAISE EXCEPTION 'only COUNTRY can be a root org unit' USING ERRCODE = '23514';
    END IF;
    NEW.path := goye_unit_label(NEW.id);
    RETURN NEW;
  END IF;

  SELECT type, path, is_active INTO parent_type, parent_path, parent_active
  FROM org_units
  WHERE id = NEW.parent_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'parent org unit does not exist' USING ERRCODE = '23503';
  END IF;
  IF NOT parent_active THEN
    RAISE EXCEPTION 'cannot create a child under an inactive org unit' USING ERRCODE = '23514';
  END IF;
  IF parent_type <> goye_expected_parent_type(NEW.type) THEN
    RAISE EXCEPTION 'invalid parent type % for child type %', parent_type, NEW.type
      USING ERRCODE = '23514';
  END IF;

  NEW.path := parent_path || goye_unit_label(NEW.id);
  RETURN NEW;
END;
$$;

CREATE TRIGGER org_units_prepare_before_write
BEFORE INSERT OR UPDATE ON org_units
FOR EACH ROW EXECUTE FUNCTION goye_prepare_org_unit();

CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  home_unit_id uuid REFERENCES org_units(id) ON DELETE RESTRICT,
  phone_normalized text UNIQUE,
  email_normalized text UNIQUE,
  display_name text NOT NULL,
  status user_status NOT NULL DEFAULT 'INVITED',
  last_login_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deactivated_at timestamptz,
  CONSTRAINT users_identity_required CHECK (phone_normalized IS NOT NULL OR email_normalized IS NOT NULL),
  CONSTRAINT users_phone_format CHECK (phone_normalized IS NULL OR phone_normalized ~ '^\\+[1-9][0-9]{6,14}$'),
  CONSTRAINT users_email_normalized CHECK (email_normalized IS NULL OR email_normalized = lower(email_normalized)),
  CONSTRAINT users_display_name_not_blank CHECK (length(btrim(display_name)) > 0),
  CONSTRAINT users_deactivation_consistent CHECK (
    (status <> 'DEACTIVATED' AND deactivated_at IS NULL) OR (status = 'DEACTIVATED' AND deactivated_at IS NOT NULL)
  )
);
CREATE INDEX users_home_unit_id_idx ON users (home_unit_id);
CREATE INDEX users_status_idx ON users (status);

CREATE TABLE user_roles (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role_id uuid NOT NULL REFERENCES roles(id) ON DELETE RESTRICT,
  assigned_by uuid REFERENCES users(id) ON DELETE SET NULL,
  assigned_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, role_id)
);
CREATE INDEX user_roles_role_id_idx ON user_roles (role_id);

CREATE TABLE devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_identifier_hash text NOT NULL,
  platform device_platform NOT NULL DEFAULT 'UNKNOWN',
  label text,
  push_token_encrypted bytea,
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT devices_user_identifier_unique UNIQUE (user_id, device_identifier_hash)
);
CREATE INDEX devices_user_id_idx ON devices (user_id);

CREATE TABLE sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id uuid REFERENCES devices(id) ON DELETE SET NULL,
  refresh_token_hash text NOT NULL UNIQUE,
  status session_status NOT NULL DEFAULT 'ACTIVE',
  issued_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  last_used_at timestamptz,
  revoked_at timestamptz,
  revoked_reason text,
  replaced_by_session_id uuid REFERENCES sessions(id) ON DELETE SET NULL,
  ip_hash text,
  user_agent_hash text,
  CONSTRAINT sessions_expiry_after_issue CHECK (expires_at > issued_at),
  CONSTRAINT sessions_revocation_consistent CHECK (
    (status = 'ACTIVE' AND revoked_at IS NULL) OR (status <> 'ACTIVE' AND revoked_at IS NOT NULL)
  )
);
CREATE INDEX sessions_user_status_idx ON sessions (user_id, status, expires_at);
CREATE INDEX sessions_device_id_idx ON sessions (device_id);

CREATE TABLE audit_chain_state (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  latest_hash text NOT NULL DEFAULT repeat('0', 64),
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO audit_chain_state (singleton) VALUES (true) ON CONFLICT (singleton) DO NOTHING;

CREATE TABLE audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  occurred_at timestamptz NOT NULL DEFAULT now(),
  actor_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  action text NOT NULL,
  resource_type text NOT NULL,
  resource_id uuid,
  scope_unit_id uuid REFERENCES org_units(id) ON DELETE SET NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  previous_hash text NOT NULL,
  entry_hash text NOT NULL UNIQUE,
  CONSTRAINT audit_action_not_blank CHECK (length(btrim(action)) > 0),
  CONSTRAINT audit_resource_type_not_blank CHECK (length(btrim(resource_type)) > 0),
  CONSTRAINT audit_hashes_hex CHECK (previous_hash ~ '^[0-9a-f]{64}$' AND entry_hash ~ '^[0-9a-f]{64}$')
);
CREATE INDEX audit_log_occurred_at_idx ON audit_log (occurred_at DESC);
CREATE INDEX audit_log_resource_idx ON audit_log (resource_type, resource_id);
CREATE INDEX audit_log_actor_idx ON audit_log (actor_user_id, occurred_at DESC);

CREATE OR REPLACE FUNCTION goye_reject_audit_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'audit_log is append-only' USING ERRCODE = '55000';
END;
$$;

CREATE TRIGGER audit_log_no_update_or_delete
BEFORE UPDATE OR DELETE ON audit_log
FOR EACH ROW EXECUTE FUNCTION goye_reject_audit_mutation();
