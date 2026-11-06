-- Server-set PostgreSQL RLS policy layer. API predicates remain required as a second layer.
-- Rollback: run 0004_row_level_security.down.sql to remove policies before dropping tables.

-- Migrations run under a privileged owner. Runtime calls always SET LOCAL ROLE to this
-- non-superuser, non-BYPASSRLS role before an actor context is applied.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'goye_runtime') THEN
    CREATE ROLE goye_runtime NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
  END IF;
END;
$$;
GRANT goye_runtime TO CURRENT_USER;
GRANT USAGE ON SCHEMA public TO goye_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
  roles, org_units, users, user_roles, devices, sessions, otp_challenges,
  auth_lockouts, audit_chain_state, audit_log
TO goye_runtime;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO goye_runtime;

CREATE OR REPLACE FUNCTION goye_setting_is_true(setting_name text)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(NULLIF(current_setting(setting_name, true), ''), 'false')::boolean;
$$;

CREATE OR REPLACE FUNCTION goye_actor_home_path()
RETURNS ltree
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('goye.home_path', true), '')::ltree;
$$;

CREATE OR REPLACE FUNCTION goye_actor_user_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('goye.user_id', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION goye_is_system_actor()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT goye_setting_is_true('goye.is_system');
$$;

CREATE OR REPLACE FUNCTION goye_is_global_admin()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT goye_setting_is_true('goye.is_global_admin');
$$;

ALTER TABLE roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE roles FORCE ROW LEVEL SECURITY;
CREATE POLICY roles_select ON roles FOR SELECT
  USING (goye_is_system_actor() OR goye_is_global_admin());
CREATE POLICY roles_write ON roles FOR ALL
  USING (goye_is_system_actor() OR goye_is_global_admin())
  WITH CHECK (goye_is_system_actor() OR goye_is_global_admin());

ALTER TABLE org_units ENABLE ROW LEVEL SECURITY;
ALTER TABLE org_units FORCE ROW LEVEL SECURITY;
CREATE POLICY org_units_select_scope ON org_units FOR SELECT
  USING (
    goye_is_system_actor()
    OR goye_is_global_admin()
    OR (goye_actor_home_path() IS NOT NULL AND path <@ goye_actor_home_path())
  );
CREATE POLICY org_units_write_global ON org_units FOR ALL
  USING (goye_is_system_actor() OR goye_is_global_admin())
  WITH CHECK (goye_is_system_actor() OR goye_is_global_admin());

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE users FORCE ROW LEVEL SECURITY;
CREATE POLICY users_select_scope ON users FOR SELECT
  USING (
    goye_is_system_actor()
    OR goye_is_global_admin()
    OR id = goye_actor_user_id()
    OR EXISTS (
      SELECT 1 FROM org_units scoped_home
      WHERE scoped_home.id = users.home_unit_id
      AND goye_actor_home_path() IS NOT NULL
      AND scoped_home.path <@ goye_actor_home_path()
    )
  );
CREATE POLICY users_write_global ON users FOR ALL
  USING (goye_is_system_actor() OR goye_is_global_admin())
  WITH CHECK (goye_is_system_actor() OR goye_is_global_admin());

ALTER TABLE user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_roles FORCE ROW LEVEL SECURITY;
CREATE POLICY user_roles_select_scope ON user_roles FOR SELECT
  USING (
    goye_is_system_actor()
    OR goye_is_global_admin()
    OR user_id = goye_actor_user_id()
    OR EXISTS (
      SELECT 1
      FROM users scoped_user
      JOIN org_units scoped_home ON scoped_home.id = scoped_user.home_unit_id
      WHERE scoped_user.id = user_roles.user_id
      AND goye_actor_home_path() IS NOT NULL
      AND scoped_home.path <@ goye_actor_home_path()
    )
  );
CREATE POLICY user_roles_write_global ON user_roles FOR ALL
  USING (goye_is_system_actor() OR goye_is_global_admin())
  WITH CHECK (goye_is_system_actor() OR goye_is_global_admin());

ALTER TABLE devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE devices FORCE ROW LEVEL SECURITY;
CREATE POLICY devices_own_or_global ON devices FOR ALL
  USING (goye_is_system_actor() OR goye_is_global_admin() OR user_id = goye_actor_user_id())
  WITH CHECK (goye_is_system_actor() OR goye_is_global_admin() OR user_id = goye_actor_user_id());

ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE sessions FORCE ROW LEVEL SECURITY;
CREATE POLICY sessions_own_or_global ON sessions FOR ALL
  USING (goye_is_system_actor() OR goye_is_global_admin() OR user_id = goye_actor_user_id())
  WITH CHECK (goye_is_system_actor() OR goye_is_global_admin() OR user_id = goye_actor_user_id());

ALTER TABLE otp_challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE otp_challenges FORCE ROW LEVEL SECURITY;
CREATE POLICY otp_challenges_system_only ON otp_challenges FOR ALL
  USING (goye_is_system_actor())
  WITH CHECK (goye_is_system_actor());

ALTER TABLE auth_lockouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth_lockouts FORCE ROW LEVEL SECURITY;
CREATE POLICY auth_lockouts_system_only ON auth_lockouts FOR ALL
  USING (goye_is_system_actor())
  WITH CHECK (goye_is_system_actor());

ALTER TABLE audit_chain_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_chain_state FORCE ROW LEVEL SECURITY;
CREATE POLICY audit_chain_state_system_only ON audit_chain_state FOR ALL
  USING (goye_is_system_actor())
  WITH CHECK (goye_is_system_actor());

ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log FORCE ROW LEVEL SECURITY;
CREATE POLICY audit_log_select_global ON audit_log FOR SELECT
  USING (goye_is_system_actor() OR goye_is_global_admin());
CREATE POLICY audit_log_insert_system_or_global ON audit_log FOR INSERT
  WITH CHECK (goye_is_system_actor() OR goye_is_global_admin());

GRANT EXECUTE ON FUNCTION goye_append_audit_event(uuid, text, text, uuid, uuid, jsonb) TO goye_runtime;
