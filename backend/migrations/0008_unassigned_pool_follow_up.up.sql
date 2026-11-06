-- Phase 2 Unassigned Pool and first parish follow-up plan.
-- Rollback: run 0008_unassigned_pool_follow_up.down.sql before rolling back convert capture.

CREATE TYPE follow_up_task_type AS ENUM ('CALL_24H', 'PRAYER_DAY_3', 'VISIT_DAY_7');
CREATE TYPE follow_up_task_status AS ENUM ('PENDING', 'COMPLETED', 'CANCELLED');

ALTER TABLE converts
  ADD COLUMN assigned_at timestamptz,
  ADD COLUMN assigned_by uuid REFERENCES users(id) ON DELETE RESTRICT;

CREATE TABLE follow_up_tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  convert_id uuid NOT NULL REFERENCES converts(id) ON DELETE RESTRICT,
  parish_id uuid NOT NULL REFERENCES org_units(id) ON DELETE RESTRICT,
  task_type follow_up_task_type NOT NULL,
  due_at timestamptz NOT NULL,
  status follow_up_task_status NOT NULL DEFAULT 'PENDING',
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  CONSTRAINT follow_up_tasks_convert_type_unique UNIQUE (convert_id, task_type),
  CONSTRAINT follow_up_tasks_completion_consistent CHECK (
    (status = 'COMPLETED' AND completed_at IS NOT NULL)
    OR (status <> 'COMPLETED' AND completed_at IS NULL)
  )
);
CREATE INDEX follow_up_tasks_parish_due_idx
  ON follow_up_tasks (parish_id, due_at) WHERE status = 'PENDING';
CREATE INDEX follow_up_tasks_convert_idx ON follow_up_tasks (convert_id);

-- Convert contact updates are column-limited. Parish assignment must use the controlled function below.
REVOKE UPDATE ON TABLE converts FROM goye_runtime;
GRANT UPDATE (full_name_encrypted, phone_encrypted, address_encrypted) ON TABLE converts TO goye_runtime;
GRANT SELECT ON TABLE follow_up_tasks TO goye_runtime;

ALTER TABLE follow_up_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE follow_up_tasks FORCE ROW LEVEL SECURITY;
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
CREATE POLICY follow_up_tasks_insert_scope ON follow_up_tasks FOR INSERT
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
  target_path ltree;
  target_type org_unit_type;
  target_active boolean;
  assignment_time timestamptz := now();
BEGIN
  SELECT registered.path, c.parish_id
  INTO source_path, existing_parish_id
  FROM converts c
  JOIN org_units registered ON registered.id = c.registered_at_unit_id
  WHERE c.id = p_convert_id
  FOR UPDATE OF c;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'convert not found in actor scope' USING ERRCODE = 'P0002';
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

REVOKE ALL ON FUNCTION goye_assign_convert_to_parish(uuid, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION goye_assign_convert_to_parish(uuid, uuid, uuid) TO goye_runtime;
