-- Roll back Phase 2 privacy removal workflow and restore the pre-privacy routine workflow functions.

DROP TRIGGER IF EXISTS converts_maintain_rollup_after_write ON converts;

REVOKE EXECUTE ON FUNCTION goye_request_convert_removal(uuid, uuid, bytea) FROM goye_runtime;
REVOKE EXECUTE ON FUNCTION goye_resolve_convert_removal(uuid, privacy_removal_resolution, uuid, bytea, bytea) FROM goye_runtime;
DROP FUNCTION IF EXISTS goye_request_convert_removal(uuid, uuid, bytea);
DROP FUNCTION IF EXISTS goye_resolve_convert_removal(uuid, privacy_removal_resolution, uuid, bytea, bytea);

CREATE OR REPLACE FUNCTION goye_assign_convert_to_parish(
  p_convert_id uuid,
  p_parish_id uuid,
  p_assigned_by uuid
)
RETURNS TABLE (convert_id uuid, parish_id uuid, assigned_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  source_path ltree;
  existing_parish_id uuid;
  target_path ltree;
  target_type org_unit_type;
  target_active boolean;
  assignment_time timestamptz := now();
BEGIN
  SELECT registered.path, convert.parish_id INTO source_path, existing_parish_id
  FROM converts convert
  JOIN org_units registered ON registered.id = convert.registered_at_unit_id
  WHERE convert.id = p_convert_id FOR UPDATE OF convert;
  IF NOT FOUND THEN RAISE EXCEPTION 'convert not found in actor scope' USING ERRCODE = 'P0002'; END IF;
  IF existing_parish_id IS NOT NULL THEN RAISE EXCEPTION 'convert is already assigned to a parish' USING ERRCODE = '22023'; END IF;
  SELECT type, path, is_active INTO target_type, target_path, target_active FROM org_units WHERE id = p_parish_id;
  IF NOT FOUND OR target_type <> 'PARISH' OR NOT target_active THEN RAISE EXCEPTION 'target must be an active parish' USING ERRCODE = '22023'; END IF;
  IF NOT (target_path <@ source_path) THEN RAISE EXCEPTION 'target parish must be a descendant of the registration unit' USING ERRCODE = '22023'; END IF;
  UPDATE converts SET parish_id = p_parish_id, assigned_at = assignment_time, assigned_by = p_assigned_by WHERE id = p_convert_id;
  INSERT INTO follow_up_tasks (convert_id, parish_id, task_type, due_at) VALUES
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
RETURNS TABLE (source_convert_id uuid, target_convert_id uuid)
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
BEGIN
  IF p_source_convert_id = p_target_convert_id THEN RAISE EXCEPTION 'a convert cannot be merged into itself' USING ERRCODE = '22023'; END IF;
  SELECT registered.path, convert.parish_id, convert.merged_into_id
  INTO source_registration_path, source_parish_id, source_merged_into_id
  FROM converts convert JOIN org_units registered ON registered.id = convert.registered_at_unit_id
  WHERE convert.id = p_source_convert_id FOR UPDATE OF convert;
  IF NOT FOUND THEN RAISE EXCEPTION 'source convert not found in actor scope' USING ERRCODE = 'P0002'; END IF;
  SELECT registered.path, convert.parish_id, convert.merged_into_id
  INTO target_registration_path, target_parish_id, target_merged_into_id
  FROM converts convert JOIN org_units registered ON registered.id = convert.registered_at_unit_id
  WHERE convert.id = p_target_convert_id FOR UPDATE OF convert;
  IF NOT FOUND THEN RAISE EXCEPTION 'target convert not found in actor scope' USING ERRCODE = 'P0002'; END IF;
  IF source_merged_into_id IS NOT NULL OR target_merged_into_id IS NOT NULL THEN RAISE EXCEPTION 'merged converts cannot be merged again' USING ERRCODE = '22023'; END IF;
  IF subpath(source_registration_path, 0, 1) <> subpath(target_registration_path, 0, 1) THEN RAISE EXCEPTION 'converts from different countries cannot be merged' USING ERRCODE = '22023'; END IF;
  IF source_parish_id IS NOT NULL AND target_parish_id IS NOT NULL AND source_parish_id <> target_parish_id THEN RAISE EXCEPTION 'converts assigned to different parishes cannot be merged' USING ERRCODE = '22023'; END IF;
  IF target_parish_id IS NULL AND source_parish_id IS NOT NULL THEN
    UPDATE converts SET parish_id = source_parish_id, assigned_at = COALESCE(assigned_at, now()), assigned_by = COALESCE(assigned_by, p_merged_by) WHERE id = p_target_convert_id;
  END IF;
  UPDATE follow_up_tasks source_task SET status = 'CANCELLED' FROM follow_up_tasks target_task
  WHERE source_task.convert_id = p_source_convert_id AND target_task.convert_id = p_target_convert_id
    AND source_task.task_type = target_task.task_type AND source_task.status = 'PENDING' AND target_task.status = 'PENDING';
  UPDATE follow_up_tasks SET convert_id = p_target_convert_id WHERE convert_id = p_source_convert_id AND status <> 'CANCELLED';
  UPDATE converts SET merged_into_id = p_target_convert_id, merged_at = now(), merged_by = p_merged_by WHERE id = p_source_convert_id;
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
DECLARE event_id uuid;
BEGIN
  IF NOT goye_is_system_actor() AND p_actor_user_id IS DISTINCT FROM goye_actor_user_id() THEN
    RAISE EXCEPTION 'timeline actor must match the active actor' USING ERRCODE = '42501';
  END IF;
  PERFORM 1 FROM converts WHERE id = p_convert_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'convert not found in actor scope' USING ERRCODE = 'P0002'; END IF;
  INSERT INTO convert_timeline_events (convert_id, event_type, actor_user_id, note_encrypted, metadata)
  VALUES (p_convert_id, p_event_type, p_actor_user_id, p_note_encrypted, COALESCE(p_metadata, '{}'::jsonb)) RETURNING id INTO event_id;
  RETURN event_id;
END;
$$;

CREATE OR REPLACE FUNCTION goye_advance_convert_stage(
  p_convert_id uuid,
  p_target_stage convert_stage,
  p_actor_user_id uuid,
  p_note_encrypted bytea DEFAULT NULL
)
RETURNS TABLE (convert_id uuid, previous_stage convert_stage, current_stage convert_stage, stage_changed_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE old_stage convert_stage; assigned_parish_id uuid; changed_at timestamptz := now();
BEGIN
  IF NOT goye_is_system_actor() AND p_actor_user_id IS DISTINCT FROM goye_actor_user_id() THEN RAISE EXCEPTION 'stage actor must match the active actor' USING ERRCODE = '42501'; END IF;
  SELECT stage, parish_id INTO old_stage, assigned_parish_id FROM converts WHERE id = p_convert_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'convert not found in actor scope' USING ERRCODE = 'P0002'; END IF;
  IF assigned_parish_id IS NULL THEN RAISE EXCEPTION 'a convert must be assigned to a parish before advancing stages' USING ERRCODE = '22023'; END IF;
  IF goye_convert_stage_rank(p_target_stage) <> goye_convert_stage_rank(old_stage) + 1 THEN RAISE EXCEPTION 'stage transitions must advance exactly one configured step' USING ERRCODE = '22023'; END IF;
  UPDATE converts SET stage = p_target_stage, stage_changed_at = changed_at WHERE id = p_convert_id;
  INSERT INTO convert_timeline_events (convert_id, event_type, from_stage, to_stage, note_encrypted, actor_user_id)
  VALUES (p_convert_id, 'STAGE_ADVANCED', old_stage, p_target_stage, p_note_encrypted, p_actor_user_id);
  RETURN QUERY SELECT p_convert_id, old_stage, p_target_stage, changed_at;
END;
$$;

CREATE OR REPLACE FUNCTION goye_maintain_convert_rollup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE old_counted_at_unit_id uuid; new_counted_at_unit_id uuid; old_counted boolean; new_counted boolean;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.merged_into_id IS NULL THEN
      PERFORM goye_apply_convert_rollup(COALESCE(NEW.parish_id, NEW.registered_at_unit_id), NEW.created_at::date, NEW.stage, 1);
    END IF;
    RETURN NEW;
  END IF;
  old_counted := OLD.merged_into_id IS NULL;
  new_counted := NEW.merged_into_id IS NULL;
  old_counted_at_unit_id := COALESCE(OLD.parish_id, OLD.registered_at_unit_id);
  new_counted_at_unit_id := COALESCE(NEW.parish_id, NEW.registered_at_unit_id);
  IF old_counted AND (NOT new_counted OR old_counted_at_unit_id IS DISTINCT FROM new_counted_at_unit_id OR OLD.created_at::date IS DISTINCT FROM NEW.created_at::date OR OLD.stage IS DISTINCT FROM NEW.stage) THEN
    PERFORM goye_apply_convert_rollup(old_counted_at_unit_id, OLD.created_at::date, OLD.stage, -1);
  END IF;
  IF new_counted AND (NOT old_counted OR old_counted_at_unit_id IS DISTINCT FROM new_counted_at_unit_id OR OLD.created_at::date IS DISTINCT FROM NEW.created_at::date OR OLD.stage IS DISTINCT FROM NEW.stage) THEN
    PERFORM goye_apply_convert_rollup(new_counted_at_unit_id, NEW.created_at::date, NEW.stage, 1);
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER converts_maintain_rollup_after_write
AFTER INSERT OR UPDATE OF registered_at_unit_id, parish_id, created_at, stage, merged_into_id ON converts
FOR EACH ROW EXECUTE FUNCTION goye_maintain_convert_rollup();

DROP POLICY IF EXISTS converts_select_scope ON converts;
CREATE POLICY converts_select_scope ON converts FOR SELECT
  USING (
    goye_is_system_actor() OR goye_is_global_admin()
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
  );
DROP POLICY IF EXISTS converts_update_scope ON converts;
CREATE POLICY converts_update_scope ON converts FOR UPDATE
  USING (
    goye_is_system_actor() OR goye_is_global_admin()
    OR EXISTS (SELECT 1 FROM org_units registered_unit WHERE registered_unit.id = converts.registered_at_unit_id AND goye_actor_home_path() IS NOT NULL AND registered_unit.path <@ goye_actor_home_path())
    OR EXISTS (SELECT 1 FROM org_units assigned_parish WHERE assigned_parish.id = converts.parish_id AND goye_actor_home_path() IS NOT NULL AND assigned_parish.path <@ goye_actor_home_path())
  )
  WITH CHECK (
    goye_is_system_actor() OR goye_is_global_admin()
    OR EXISTS (SELECT 1 FROM org_units registered_unit WHERE registered_unit.id = converts.registered_at_unit_id AND goye_actor_home_path() IS NOT NULL AND registered_unit.path <@ goye_actor_home_path())
    OR EXISTS (SELECT 1 FROM org_units assigned_parish WHERE assigned_parish.id = converts.parish_id AND goye_actor_home_path() IS NOT NULL AND assigned_parish.path <@ goye_actor_home_path())
  );

DROP POLICY IF EXISTS follow_up_tasks_select_scope ON follow_up_tasks;
CREATE POLICY follow_up_tasks_select_scope ON follow_up_tasks FOR SELECT
  USING (
    goye_is_system_actor()
    OR goye_is_global_admin()
    OR EXISTS (
      SELECT 1 FROM org_units parish
      WHERE parish.id = follow_up_tasks.parish_id
      AND goye_actor_home_path() IS NOT NULL
      AND parish.path <@ goye_actor_home_path()
    )
  );
DROP POLICY IF EXISTS follow_up_tasks_update_scope ON follow_up_tasks;
CREATE POLICY follow_up_tasks_update_scope ON follow_up_tasks FOR UPDATE
  USING (
    goye_is_system_actor()
    OR goye_is_global_admin()
    OR EXISTS (
      SELECT 1 FROM org_units parish
      WHERE parish.id = follow_up_tasks.parish_id
      AND goye_actor_home_path() IS NOT NULL
      AND parish.path <@ goye_actor_home_path()
    )
  )
  WITH CHECK (
    goye_is_system_actor()
    OR goye_is_global_admin()
    OR EXISTS (
      SELECT 1 FROM org_units parish
      WHERE parish.id = follow_up_tasks.parish_id
      AND goye_actor_home_path() IS NOT NULL
      AND parish.path <@ goye_actor_home_path()
    )
  );

DROP TABLE IF EXISTS convert_removal_requests;
DROP FUNCTION IF EXISTS goye_is_privacy_officer();
DROP INDEX IF EXISTS converts_routine_access_idx;
ALTER TABLE converts DROP COLUMN IF EXISTS privacy_status;
DROP TYPE IF EXISTS privacy_removal_resolution;
DROP TYPE IF EXISTS privacy_removal_request_status;
DROP TYPE IF EXISTS convert_privacy_status;
