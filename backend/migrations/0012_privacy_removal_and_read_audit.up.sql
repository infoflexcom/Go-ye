-- Phase 2 privacy removal workflow and protected routine access.
-- Rollback: run 0012_privacy_removal_and_read_audit.down.sql before rolling back roll-up summaries.

CREATE TYPE convert_privacy_status AS ENUM ('ACTIVE', 'REMOVAL_REQUESTED', 'ANONYMISED');
CREATE TYPE privacy_removal_request_status AS ENUM ('PENDING', 'ANONYMISED', 'REJECTED');
CREATE TYPE privacy_removal_resolution AS ENUM ('ANONYMISE', 'REJECT');

ALTER TABLE converts
  ADD COLUMN privacy_status convert_privacy_status NOT NULL DEFAULT 'ACTIVE';
CREATE INDEX converts_routine_access_idx
  ON converts (privacy_status, registered_at_unit_id, created_at DESC)
  WHERE privacy_status = 'ACTIVE' AND merged_into_id IS NULL;

CREATE TABLE convert_removal_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  convert_id uuid NOT NULL REFERENCES converts(id) ON DELETE RESTRICT,
  requested_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  reason_encrypted bytea,
  status privacy_removal_request_status NOT NULL DEFAULT 'PENDING',
  requested_at timestamptz NOT NULL DEFAULT now(),
  resolved_by uuid REFERENCES users(id) ON DELETE RESTRICT,
  resolution_note_encrypted bytea,
  resolved_at timestamptz,
  CONSTRAINT convert_removal_requests_reason_encrypted_shape CHECK (
    reason_encrypted IS NULL OR octet_length(reason_encrypted) > 29
  ),
  CONSTRAINT convert_removal_requests_note_encrypted_shape CHECK (
    resolution_note_encrypted IS NULL OR octet_length(resolution_note_encrypted) > 29
  ),
  CONSTRAINT convert_removal_requests_resolution_shape CHECK (
    (status = 'PENDING' AND resolved_by IS NULL AND resolved_at IS NULL AND resolution_note_encrypted IS NULL)
    OR (status IN ('ANONYMISED', 'REJECTED') AND resolved_by IS NOT NULL AND resolved_at IS NOT NULL)
  )
);
CREATE INDEX convert_removal_requests_pending_idx
  ON convert_removal_requests (status, requested_at ASC);
CREATE UNIQUE INDEX convert_removal_requests_one_pending_per_convert_idx
  ON convert_removal_requests (convert_id) WHERE status = 'PENDING';

-- A privacy officer is an explicitly marked request actor, not a database superuser.
CREATE OR REPLACE FUNCTION goye_is_privacy_officer()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT goye_setting_is_true('goye.is_privacy_officer');
$$;

-- Pending requests are hidden from ordinary operational reads, including Global Admin
-- routine reads. A scoped Privacy Officer (or a migration/system transaction) can process them.
DROP POLICY IF EXISTS converts_select_scope ON converts;
CREATE POLICY converts_select_scope ON converts FOR SELECT
  USING (
    goye_is_system_actor()
    OR (
      goye_is_privacy_officer()
      AND (
        goye_is_global_admin()
        OR EXISTS (
          SELECT 1 FROM org_units registered_unit
          WHERE registered_unit.id = converts.registered_at_unit_id
          AND goye_actor_home_path() IS NOT NULL
          AND registered_unit.path <@ goye_actor_home_path()
        )
        OR EXISTS (
          SELECT 1 FROM org_units assigned_parish
          WHERE assigned_parish.id = converts.parish_id
          AND goye_actor_home_path() IS NOT NULL
          AND assigned_parish.path <@ goye_actor_home_path()
        )
      )
    )
    OR (
      converts.privacy_status = 'ACTIVE'
      AND (
        goye_is_global_admin()
        OR EXISTS (
          SELECT 1 FROM org_units registered_unit
          WHERE registered_unit.id = converts.registered_at_unit_id
          AND goye_actor_home_path() IS NOT NULL
          AND registered_unit.path <@ goye_actor_home_path()
        )
        OR EXISTS (
          SELECT 1 FROM org_units assigned_parish
          WHERE assigned_parish.id = converts.parish_id
          AND goye_actor_home_path() IS NOT NULL
          AND assigned_parish.path <@ goye_actor_home_path()
        )
      )
    )
  );

DROP POLICY IF EXISTS converts_update_scope ON converts;
CREATE POLICY converts_update_scope ON converts FOR UPDATE
  USING (
    goye_is_system_actor()
    OR (
      goye_is_privacy_officer()
      AND (
        goye_is_global_admin()
        OR EXISTS (
          SELECT 1 FROM org_units registered_unit
          WHERE registered_unit.id = converts.registered_at_unit_id
          AND goye_actor_home_path() IS NOT NULL
          AND registered_unit.path <@ goye_actor_home_path()
        )
        OR EXISTS (
          SELECT 1 FROM org_units assigned_parish
          WHERE assigned_parish.id = converts.parish_id
          AND goye_actor_home_path() IS NOT NULL
          AND assigned_parish.path <@ goye_actor_home_path()
        )
      )
    )
    OR (
      converts.privacy_status = 'ACTIVE'
      AND (
        goye_is_global_admin()
        OR EXISTS (
          SELECT 1 FROM org_units registered_unit
          WHERE registered_unit.id = converts.registered_at_unit_id
          AND goye_actor_home_path() IS NOT NULL
          AND registered_unit.path <@ goye_actor_home_path()
        )
        OR EXISTS (
          SELECT 1 FROM org_units assigned_parish
          WHERE assigned_parish.id = converts.parish_id
          AND goye_actor_home_path() IS NOT NULL
          AND assigned_parish.path <@ goye_actor_home_path()
        )
      )
    )
  )
  WITH CHECK (
    goye_is_system_actor()
    OR (
      goye_is_privacy_officer()
      AND (
        EXISTS (
          SELECT 1 FROM org_units registered_unit
          WHERE registered_unit.id = converts.registered_at_unit_id
          AND goye_actor_home_path() IS NOT NULL
          AND registered_unit.path <@ goye_actor_home_path()
        )
        OR EXISTS (
          SELECT 1 FROM org_units assigned_parish
          WHERE assigned_parish.id = converts.parish_id
          AND goye_actor_home_path() IS NOT NULL
          AND assigned_parish.path <@ goye_actor_home_path()
        )
      )
    )
    OR (
      converts.privacy_status = 'ACTIVE'
      AND (
        goye_is_global_admin()
        OR EXISTS (
          SELECT 1 FROM org_units registered_unit
          WHERE registered_unit.id = converts.registered_at_unit_id
          AND goye_actor_home_path() IS NOT NULL
          AND registered_unit.path <@ goye_actor_home_path()
        )
        OR EXISTS (
          SELECT 1 FROM org_units assigned_parish
          WHERE assigned_parish.id = converts.parish_id
          AND goye_actor_home_path() IS NOT NULL
          AND assigned_parish.path <@ goye_actor_home_path()
        )
      )
    )
  );

-- Pending follow-up tasks are also routine access and must disappear with the quarantined convert.
DROP POLICY IF EXISTS follow_up_tasks_select_scope ON follow_up_tasks;
CREATE POLICY follow_up_tasks_select_scope ON follow_up_tasks FOR SELECT
  USING (
    goye_is_system_actor()
    OR (
      goye_is_privacy_officer()
      AND (
        goye_is_global_admin()
        OR EXISTS (
          SELECT 1 FROM org_units parish
          WHERE parish.id = follow_up_tasks.parish_id
          AND goye_actor_home_path() IS NOT NULL
          AND parish.path <@ goye_actor_home_path()
        )
      )
    )
    OR (
      EXISTS (
        SELECT 1 FROM converts convert
        WHERE convert.id = follow_up_tasks.convert_id
          AND convert.privacy_status = 'ACTIVE'
      )
      AND (
        goye_is_global_admin()
        OR EXISTS (
          SELECT 1 FROM org_units parish
          WHERE parish.id = follow_up_tasks.parish_id
          AND goye_actor_home_path() IS NOT NULL
          AND parish.path <@ goye_actor_home_path()
        )
      )
    )
  );

DROP POLICY IF EXISTS follow_up_tasks_update_scope ON follow_up_tasks;
CREATE POLICY follow_up_tasks_update_scope ON follow_up_tasks FOR UPDATE
  USING (
    goye_is_system_actor()
    OR (
      goye_is_privacy_officer()
      AND (
        goye_is_global_admin()
        OR EXISTS (
          SELECT 1 FROM org_units parish
          WHERE parish.id = follow_up_tasks.parish_id
          AND goye_actor_home_path() IS NOT NULL
          AND parish.path <@ goye_actor_home_path()
        )
      )
    )
    OR (
      EXISTS (
        SELECT 1 FROM converts convert
        WHERE convert.id = follow_up_tasks.convert_id
          AND convert.privacy_status = 'ACTIVE'
      )
      AND (
        goye_is_global_admin()
        OR EXISTS (
          SELECT 1 FROM org_units parish
          WHERE parish.id = follow_up_tasks.parish_id
          AND goye_actor_home_path() IS NOT NULL
          AND parish.path <@ goye_actor_home_path()
        )
      )
    )
  )
  WITH CHECK (
    goye_is_system_actor()
    OR (
      goye_is_privacy_officer()
      AND (
        goye_is_global_admin()
        OR EXISTS (
          SELECT 1 FROM org_units parish
          WHERE parish.id = follow_up_tasks.parish_id
          AND goye_actor_home_path() IS NOT NULL
          AND parish.path <@ goye_actor_home_path()
        )
      )
    )
    OR (
      EXISTS (
        SELECT 1 FROM converts convert
        WHERE convert.id = follow_up_tasks.convert_id
          AND convert.privacy_status = 'ACTIVE'
      )
      AND (
        goye_is_global_admin()
        OR EXISTS (
          SELECT 1 FROM org_units parish
          WHERE parish.id = follow_up_tasks.parish_id
          AND goye_actor_home_path() IS NOT NULL
          AND parish.path <@ goye_actor_home_path()
        )
      )
    )
  );

GRANT SELECT ON TABLE convert_removal_requests TO goye_runtime;
ALTER TABLE convert_removal_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE convert_removal_requests FORCE ROW LEVEL SECURITY;
CREATE POLICY convert_removal_requests_select_privacy_scope ON convert_removal_requests FOR SELECT
  USING (
    goye_is_system_actor()
    OR (
      goye_is_privacy_officer()
      AND (
        goye_is_global_admin()
        OR EXISTS (
          SELECT 1
          FROM converts convert
        LEFT JOIN org_units registered_unit ON registered_unit.id = convert.registered_at_unit_id
        LEFT JOIN org_units assigned_parish ON assigned_parish.id = convert.parish_id
        WHERE convert.id = convert_removal_requests.convert_id
          AND goye_actor_home_path() IS NOT NULL
          AND (
            registered_unit.path <@ goye_actor_home_path()
            OR assigned_parish.path <@ goye_actor_home_path()
          )
      )
      )
    )
  );

CREATE OR REPLACE FUNCTION goye_request_convert_removal(
  p_convert_id uuid,
  p_requested_by uuid,
  p_reason_encrypted bytea DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  request_id uuid;
  current_privacy_status convert_privacy_status;
  current_merged_into_id uuid;
  registration_path ltree;
  parish_path ltree;
BEGIN
  IF NOT goye_is_system_actor() AND p_requested_by IS DISTINCT FROM goye_actor_user_id() THEN
    RAISE EXCEPTION 'removal requester must match the active actor' USING ERRCODE = '42501';
  END IF;
  IF NOT goye_is_system_actor() AND NOT goye_is_global_admin() AND NOT EXISTS (
    SELECT 1
    FROM user_roles user_role
    JOIN roles role ON role.id = user_role.role_id
    WHERE user_role.user_id = goye_actor_user_id()
      AND role.key IN (
        'COUNTRY_ADMIN', 'REGION_LEADER', 'PROVINCE_LEADER', 'ZONE_LEADER', 'AREA_LEADER',
        'PARISH_PASTOR', 'SOUL_WINNER', 'FOLLOW_UP_WORKER', 'PRIVACY_OFFICER'
      )
  ) THEN
    RAISE EXCEPTION 'active actor is not permitted to request convert removal' USING ERRCODE = '42501';
  END IF;

  SELECT convert.privacy_status, convert.merged_into_id, registered_unit.path, assigned_parish.path
  INTO current_privacy_status, current_merged_into_id, registration_path, parish_path
  FROM converts convert
  JOIN org_units registered_unit ON registered_unit.id = convert.registered_at_unit_id
  LEFT JOIN org_units assigned_parish ON assigned_parish.id = convert.parish_id
  WHERE convert.id = p_convert_id
  FOR UPDATE OF convert;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'convert not found in actor scope' USING ERRCODE = 'P0002';
  END IF;
  IF NOT goye_is_system_actor() AND NOT goye_is_global_admin() AND (
    goye_actor_home_path() IS NULL
    OR NOT (
      registration_path <@ goye_actor_home_path()
      OR (parish_path IS NOT NULL AND parish_path <@ goye_actor_home_path())
    )
  ) THEN
    RAISE EXCEPTION 'convert not found in actor scope' USING ERRCODE = 'P0002';
  END IF;
  IF current_merged_into_id IS NOT NULL THEN
    RAISE EXCEPTION 'a merged source convert cannot receive a removal request' USING ERRCODE = '22023';
  END IF;
  IF current_privacy_status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'convert already has an active privacy restriction' USING ERRCODE = '22023';
  END IF;

  INSERT INTO convert_removal_requests (convert_id, requested_by, reason_encrypted)
  VALUES (p_convert_id, p_requested_by, p_reason_encrypted)
  RETURNING id INTO request_id;
  UPDATE converts
  SET privacy_status = 'REMOVAL_REQUESTED'
  WHERE id = p_convert_id;
  RETURN request_id;
END;
$$;

CREATE OR REPLACE FUNCTION goye_resolve_convert_removal(
  p_request_id uuid,
  p_resolution privacy_removal_resolution,
  p_resolved_by uuid,
  p_anonymised_name_encrypted bytea,
  p_resolution_note_encrypted bytea DEFAULT NULL
)
RETURNS TABLE (
  convert_id uuid,
  request_status privacy_removal_request_status
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  target_convert_id uuid;
  current_request_status privacy_removal_request_status;
  registration_path ltree;
  parish_path ltree;
  resolved_at_time timestamptz := now();
BEGIN
  IF NOT goye_is_system_actor() AND p_resolved_by IS DISTINCT FROM goye_actor_user_id() THEN
    RAISE EXCEPTION 'privacy resolver must match the active actor' USING ERRCODE = '42501';
  END IF;
  IF NOT goye_is_system_actor() AND NOT goye_is_global_admin() AND NOT goye_is_privacy_officer() THEN
    RAISE EXCEPTION 'a Privacy Officer is required to resolve removal requests' USING ERRCODE = '42501';
  END IF;

  SELECT request.convert_id, request.status, registered_unit.path, assigned_parish.path
  INTO target_convert_id, current_request_status, registration_path, parish_path
  FROM convert_removal_requests request
  JOIN converts convert ON convert.id = request.convert_id
  JOIN org_units registered_unit ON registered_unit.id = convert.registered_at_unit_id
  LEFT JOIN org_units assigned_parish ON assigned_parish.id = convert.parish_id
  WHERE request.id = p_request_id
  FOR UPDATE OF request, convert;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'removal request not found in privacy scope' USING ERRCODE = 'P0002';
  END IF;
  IF NOT goye_is_system_actor() AND NOT goye_is_global_admin() AND (
    goye_actor_home_path() IS NULL
    OR NOT (
      registration_path <@ goye_actor_home_path()
      OR (parish_path IS NOT NULL AND parish_path <@ goye_actor_home_path())
    )
  ) THEN
    RAISE EXCEPTION 'removal request not found in privacy scope' USING ERRCODE = 'P0002';
  END IF;
  IF current_request_status <> 'PENDING' THEN
    RAISE EXCEPTION 'removal request has already been resolved' USING ERRCODE = '22023';
  END IF;

  IF p_resolution = 'ANONYMISE' THEN
    IF octet_length(p_anonymised_name_encrypted) <= 29 THEN
      RAISE EXCEPTION 'anonymised name payload is invalid' USING ERRCODE = '22023';
    END IF;
    UPDATE converts
    SET full_name_encrypted = p_anonymised_name_encrypted,
        phone_encrypted = NULL,
        address_encrypted = NULL,
        phone_lookup_hash = NULL,
        privacy_status = 'ANONYMISED'
    WHERE id = target_convert_id;
    UPDATE follow_up_tasks task
    SET status = 'CANCELLED'
    WHERE task.convert_id = target_convert_id AND task.status = 'PENDING';
    UPDATE convert_removal_requests
    SET status = 'ANONYMISED',
        resolved_by = p_resolved_by,
        resolution_note_encrypted = p_resolution_note_encrypted,
        resolved_at = resolved_at_time
    WHERE id = p_request_id;
    RETURN QUERY SELECT target_convert_id, 'ANONYMISED'::privacy_removal_request_status;
  ELSE
    UPDATE converts
    SET privacy_status = 'ACTIVE'
    WHERE id = target_convert_id;
    UPDATE convert_removal_requests
    SET status = 'REJECTED',
        resolved_by = p_resolved_by,
        resolution_note_encrypted = p_resolution_note_encrypted,
        resolved_at = resolved_at_time
    WHERE id = p_request_id;
    RETURN QUERY SELECT target_convert_id, 'REJECTED'::privacy_removal_request_status;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION goye_request_convert_removal(uuid, uuid, bytea) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION goye_request_convert_removal(uuid, uuid, bytea) TO goye_runtime;
REVOKE ALL ON FUNCTION goye_resolve_convert_removal(uuid, privacy_removal_resolution, uuid, bytea, bytea) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION goye_resolve_convert_removal(uuid, privacy_removal_resolution, uuid, bytea, bytea) TO goye_runtime;

-- Guard existing controlled workflow functions so a hidden record cannot continue through routine work.
CREATE OR REPLACE FUNCTION goye_assign_convert_to_parish(
  p_convert_id uuid,
  p_parish_id uuid,
  p_assigned_by uuid
)
RETURNS TABLE (
  convert_id uuid,
  parish_id uuid,
  assigned_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  source_path ltree;
  existing_parish_id uuid;
  current_privacy_status convert_privacy_status;
  target_path ltree;
  target_type org_unit_type;
  target_active boolean;
  assignment_time timestamptz := now();
BEGIN
  SELECT registered.path, convert.parish_id, convert.privacy_status
  INTO source_path, existing_parish_id, current_privacy_status
  FROM converts convert
  JOIN org_units registered ON registered.id = convert.registered_at_unit_id
  WHERE convert.id = p_convert_id
  FOR UPDATE OF convert;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'convert not found in actor scope' USING ERRCODE = 'P0002';
  END IF;
  IF current_privacy_status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'convert is restricted by a privacy removal request' USING ERRCODE = '22023';
  END IF;
  IF existing_parish_id IS NOT NULL THEN
    RAISE EXCEPTION 'convert is already assigned to a parish' USING ERRCODE = '22023';
  END IF;

  SELECT type, path, is_active
  INTO target_type, target_path, target_active
  FROM org_units
  WHERE id = p_parish_id;
  IF NOT FOUND OR target_type <> 'PARISH' OR NOT target_active THEN
    RAISE EXCEPTION 'target must be an active parish' USING ERRCODE = '22023';
  END IF;
  IF NOT (target_path <@ source_path) THEN
    RAISE EXCEPTION 'target parish must be a descendant of the registration unit' USING ERRCODE = '22023';
  END IF;

  UPDATE converts
  SET parish_id = p_parish_id,
      assigned_at = assignment_time,
      assigned_by = p_assigned_by
  WHERE id = p_convert_id;

  INSERT INTO follow_up_tasks (convert_id, parish_id, task_type, due_at)
  VALUES
    (p_convert_id, p_parish_id, 'CALL_24H', assignment_time + interval '24 hours'),
    (p_convert_id, p_parish_id, 'PRAYER_DAY_3', assignment_time + interval '3 days'),
    (p_convert_id, p_parish_id, 'VISIT_DAY_7', assignment_time + interval '7 days');

  RETURN QUERY SELECT p_convert_id, p_parish_id, assignment_time;
END;
$$;

CREATE OR REPLACE FUNCTION goye_merge_converts(
  p_source_convert_id uuid,
  p_target_convert_id uuid,
  p_merged_by uuid
)
RETURNS TABLE (
  source_convert_id uuid,
  target_convert_id uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  source_registration_path ltree;
  target_registration_path ltree;
  source_parish_id uuid;
  target_parish_id uuid;
  source_merged_into_id uuid;
  target_merged_into_id uuid;
  source_privacy_status convert_privacy_status;
  target_privacy_status convert_privacy_status;
BEGIN
  IF p_source_convert_id = p_target_convert_id THEN
    RAISE EXCEPTION 'a convert cannot be merged into itself' USING ERRCODE = '22023';
  END IF;

  SELECT registered.path, convert.parish_id, convert.merged_into_id, convert.privacy_status
  INTO source_registration_path, source_parish_id, source_merged_into_id, source_privacy_status
  FROM converts convert
  JOIN org_units registered ON registered.id = convert.registered_at_unit_id
  WHERE convert.id = p_source_convert_id
  FOR UPDATE OF convert;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'source convert not found in actor scope' USING ERRCODE = 'P0002';
  END IF;

  SELECT registered.path, convert.parish_id, convert.merged_into_id, convert.privacy_status
  INTO target_registration_path, target_parish_id, target_merged_into_id, target_privacy_status
  FROM converts convert
  JOIN org_units registered ON registered.id = convert.registered_at_unit_id
  WHERE convert.id = p_target_convert_id
  FOR UPDATE OF convert;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'target convert not found in actor scope' USING ERRCODE = 'P0002';
  END IF;
  IF source_privacy_status <> 'ACTIVE' OR target_privacy_status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'a privacy-restricted convert cannot be merged' USING ERRCODE = '22023';
  END IF;
  IF source_merged_into_id IS NOT NULL OR target_merged_into_id IS NOT NULL THEN
    RAISE EXCEPTION 'merged converts cannot be merged again' USING ERRCODE = '22023';
  END IF;
  IF subpath(source_registration_path, 0, 1) <> subpath(target_registration_path, 0, 1) THEN
    RAISE EXCEPTION 'converts from different countries cannot be merged' USING ERRCODE = '22023';
  END IF;
  IF source_parish_id IS NOT NULL AND target_parish_id IS NOT NULL AND source_parish_id <> target_parish_id THEN
    RAISE EXCEPTION 'converts assigned to different parishes cannot be merged' USING ERRCODE = '22023';
  END IF;

  IF target_parish_id IS NULL AND source_parish_id IS NOT NULL THEN
    UPDATE converts
    SET parish_id = source_parish_id,
        assigned_at = COALESCE(assigned_at, now()),
        assigned_by = COALESCE(assigned_by, p_merged_by)
    WHERE id = p_target_convert_id;
  END IF;

  UPDATE follow_up_tasks source_task
  SET status = 'CANCELLED'
  FROM follow_up_tasks target_task
  WHERE source_task.convert_id = p_source_convert_id
    AND target_task.convert_id = p_target_convert_id
    AND source_task.task_type = target_task.task_type
    AND source_task.status = 'PENDING'
    AND target_task.status = 'PENDING';

  UPDATE follow_up_tasks
  SET convert_id = p_target_convert_id
  WHERE convert_id = p_source_convert_id
    AND status <> 'CANCELLED';

  UPDATE converts
  SET merged_into_id = p_target_convert_id,
      merged_at = now(),
      merged_by = p_merged_by
  WHERE id = p_source_convert_id;

  RETURN QUERY SELECT p_source_convert_id, p_target_convert_id;
END;
$$;

CREATE OR REPLACE FUNCTION goye_append_convert_timeline_event(
  p_convert_id uuid,
  p_event_type convert_timeline_event_type,
  p_actor_user_id uuid,
  p_note_encrypted bytea DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  event_id uuid;
  current_privacy_status convert_privacy_status;
BEGIN
  IF NOT goye_is_system_actor() AND p_actor_user_id IS DISTINCT FROM goye_actor_user_id() THEN
    RAISE EXCEPTION 'timeline actor must match the active actor' USING ERRCODE = '42501';
  END IF;
  SELECT privacy_status INTO current_privacy_status FROM converts WHERE id = p_convert_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'convert not found in actor scope' USING ERRCODE = 'P0002';
  END IF;
  IF current_privacy_status <> 'ACTIVE' AND NOT goye_is_system_actor() THEN
    RAISE EXCEPTION 'convert is restricted by a privacy removal request' USING ERRCODE = '22023';
  END IF;
  INSERT INTO convert_timeline_events (convert_id, event_type, actor_user_id, note_encrypted, metadata)
  VALUES (p_convert_id, p_event_type, p_actor_user_id, p_note_encrypted, COALESCE(p_metadata, '{}'::jsonb))
  RETURNING id INTO event_id;
  RETURN event_id;
END;
$$;

CREATE OR REPLACE FUNCTION goye_advance_convert_stage(
  p_convert_id uuid,
  p_target_stage convert_stage,
  p_actor_user_id uuid,
  p_note_encrypted bytea DEFAULT NULL
)
RETURNS TABLE (
  convert_id uuid,
  previous_stage convert_stage,
  current_stage convert_stage,
  stage_changed_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  old_stage convert_stage;
  assigned_parish_id uuid;
  current_privacy_status convert_privacy_status;
  changed_at timestamptz := now();
BEGIN
  IF NOT goye_is_system_actor() AND p_actor_user_id IS DISTINCT FROM goye_actor_user_id() THEN
    RAISE EXCEPTION 'stage actor must match the active actor' USING ERRCODE = '42501';
  END IF;
  SELECT stage, parish_id, privacy_status INTO old_stage, assigned_parish_id, current_privacy_status
  FROM converts
  WHERE id = p_convert_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'convert not found in actor scope' USING ERRCODE = 'P0002';
  END IF;
  IF current_privacy_status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'convert is restricted by a privacy removal request' USING ERRCODE = '22023';
  END IF;
  IF assigned_parish_id IS NULL THEN
    RAISE EXCEPTION 'a convert must be assigned to a parish before advancing stages' USING ERRCODE = '22023';
  END IF;
  IF goye_convert_stage_rank(p_target_stage) <> goye_convert_stage_rank(old_stage) + 1 THEN
    RAISE EXCEPTION 'stage transitions must advance exactly one configured step' USING ERRCODE = '22023';
  END IF;

  UPDATE converts
  SET stage = p_target_stage, stage_changed_at = changed_at
  WHERE id = p_convert_id;
  INSERT INTO convert_timeline_events (
    convert_id, event_type, from_stage, to_stage, note_encrypted, actor_user_id
  ) VALUES (
    p_convert_id, 'STAGE_ADVANCED', old_stage, p_target_stage, p_note_encrypted, p_actor_user_id
  );
  RETURN QUERY SELECT p_convert_id, old_stage, p_target_stage, changed_at;
END;
$$;

-- Keep reporting totals consistent with the privacy quarantine and irreversible anonymisation state.
CREATE OR REPLACE FUNCTION goye_maintain_convert_rollup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  old_counted_at_unit_id uuid;
  new_counted_at_unit_id uuid;
  old_counted boolean;
  new_counted boolean;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.merged_into_id IS NULL AND NEW.privacy_status = 'ACTIVE' THEN
      PERFORM goye_apply_convert_rollup(
        COALESCE(NEW.parish_id, NEW.registered_at_unit_id),
        NEW.created_at::date,
        NEW.stage,
        1
      );
    END IF;
    RETURN NEW;
  END IF;

  old_counted := OLD.merged_into_id IS NULL AND OLD.privacy_status = 'ACTIVE';
  new_counted := NEW.merged_into_id IS NULL AND NEW.privacy_status = 'ACTIVE';
  old_counted_at_unit_id := COALESCE(OLD.parish_id, OLD.registered_at_unit_id);
  new_counted_at_unit_id := COALESCE(NEW.parish_id, NEW.registered_at_unit_id);

  IF old_counted AND (
    NOT new_counted
    OR old_counted_at_unit_id IS DISTINCT FROM new_counted_at_unit_id
    OR OLD.created_at::date IS DISTINCT FROM NEW.created_at::date
    OR OLD.stage IS DISTINCT FROM NEW.stage
  ) THEN
    PERFORM goye_apply_convert_rollup(old_counted_at_unit_id, OLD.created_at::date, OLD.stage, -1);
  END IF;

  IF new_counted AND (
    NOT old_counted
    OR old_counted_at_unit_id IS DISTINCT FROM new_counted_at_unit_id
    OR OLD.created_at::date IS DISTINCT FROM NEW.created_at::date
    OR OLD.stage IS DISTINCT FROM NEW.stage
  ) THEN
    PERFORM goye_apply_convert_rollup(new_counted_at_unit_id, NEW.created_at::date, NEW.stage, 1);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS converts_maintain_rollup_after_write ON converts;
CREATE TRIGGER converts_maintain_rollup_after_write
AFTER INSERT OR UPDATE OF registered_at_unit_id, parish_id, created_at, stage, merged_into_id, privacy_status ON converts
FOR EACH ROW EXECUTE FUNCTION goye_maintain_convert_rollup();
