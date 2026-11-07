-- Roll back configurable cadence to the Phase 2 fixed three-task plan.
-- The WEEKLY_CHECK_IN enum label added by 0014 remains unused because PostgreSQL
-- cannot remove an enum value safely.

DELETE FROM follow_up_tasks WHERE task_type = 'WEEKLY_CHECK_IN';
DROP INDEX IF EXISTS follow_up_tasks_pending_cadence_due_idx;
ALTER TABLE follow_up_tasks
  DROP CONSTRAINT follow_up_tasks_convert_cadence_occurrence_unique,
  DROP COLUMN occurrence_number,
  DROP COLUMN cadence_step_id;
CREATE UNIQUE INDEX follow_up_tasks_pending_convert_type_unique
  ON follow_up_tasks (convert_id, task_type) WHERE status = 'PENDING';

DROP TRIGGER IF EXISTS follow_up_cadence_steps_prepare_before_update ON follow_up_cadence_steps;
DROP FUNCTION IF EXISTS goye_prepare_follow_up_cadence_step_update();
DROP TABLE IF EXISTS follow_up_cadence_steps;

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
