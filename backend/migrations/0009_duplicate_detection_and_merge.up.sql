-- Phase 2 duplicate detection and controlled merge.
-- Rollback: run 0009_duplicate_detection_and_merge.down.sql before rolling back the Unassigned Pool workflow.

ALTER TABLE converts
  ADD COLUMN phone_lookup_hash text,
  ADD COLUMN merged_into_id uuid REFERENCES converts(id) ON DELETE RESTRICT,
  ADD COLUMN merged_at timestamptz,
  ADD COLUMN merged_by uuid REFERENCES users(id) ON DELETE RESTRICT,
  ADD CONSTRAINT converts_merge_consistent CHECK (
    (merged_into_id IS NULL AND merged_at IS NULL AND merged_by IS NULL)
    OR (merged_into_id IS NOT NULL AND merged_at IS NOT NULL AND merged_by IS NOT NULL)
  ),
  ADD CONSTRAINT converts_cannot_merge_into_self CHECK (merged_into_id IS NULL OR merged_into_id <> id);
CREATE INDEX converts_phone_lookup_idx ON converts (phone_lookup_hash) WHERE phone_lookup_hash IS NOT NULL;
CREATE INDEX converts_merged_into_idx ON converts (merged_into_id) WHERE merged_into_id IS NOT NULL;

GRANT UPDATE (phone_lookup_hash) ON TABLE converts TO goye_runtime;

ALTER TABLE follow_up_tasks DROP CONSTRAINT follow_up_tasks_convert_type_unique;
CREATE UNIQUE INDEX follow_up_tasks_pending_convert_type_unique
  ON follow_up_tasks (convert_id, task_type) WHERE status = 'PENDING';
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
BEGIN
  IF p_source_convert_id = p_target_convert_id THEN
    RAISE EXCEPTION 'a convert cannot be merged into itself' USING ERRCODE = '22023';
  END IF;

  SELECT registered.path, c.parish_id, c.merged_into_id
  INTO source_registration_path, source_parish_id, source_merged_into_id
  FROM converts c
  JOIN org_units registered ON registered.id = c.registered_at_unit_id
  WHERE c.id = p_source_convert_id
  FOR UPDATE OF c;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'source convert not found in actor scope' USING ERRCODE = 'P0002';
  END IF;

  SELECT registered.path, c.parish_id, c.merged_into_id
  INTO target_registration_path, target_parish_id, target_merged_into_id
  FROM converts c
  JOIN org_units registered ON registered.id = c.registered_at_unit_id
  WHERE c.id = p_target_convert_id
  FOR UPDATE OF c;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'target convert not found in actor scope' USING ERRCODE = 'P0002';
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

  -- Do not leave duplicate pending actions after a merge. Historical completed/cancelled tasks remain.
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

REVOKE ALL ON FUNCTION goye_merge_converts(uuid, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION goye_merge_converts(uuid, uuid, uuid) TO goye_runtime;
