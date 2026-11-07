-- Roll back the durable scheduler/queue schema before rolling back the cadence migration.
-- PostgreSQL enum labels are intentionally not removed by the prior 0014 rollback.

REVOKE ALL ON FUNCTION goye_retry_follow_up_reminder_job(uuid, uuid, text, timestamptz, timestamptz) FROM goye_runtime;
DROP FUNCTION IF EXISTS goye_retry_follow_up_reminder_job(uuid, uuid, text, timestamptz, timestamptz);
REVOKE ALL ON FUNCTION goye_mark_follow_up_reminder_job_delivered(uuid, uuid, timestamptz) FROM goye_runtime;
DROP FUNCTION IF EXISTS goye_mark_follow_up_reminder_job_delivered(uuid, uuid, timestamptz);
REVOKE ALL ON FUNCTION goye_claim_follow_up_reminder_jobs(uuid, integer, timestamptz) FROM goye_runtime;
DROP FUNCTION IF EXISTS goye_claim_follow_up_reminder_jobs(uuid, integer, timestamptz);

DROP POLICY IF EXISTS follow_up_reminder_jobs_system_only ON follow_up_reminder_jobs;
DROP TABLE IF EXISTS follow_up_reminder_jobs;
DROP TYPE IF EXISTS follow_up_reminder_job_status;

REVOKE INSERT, UPDATE ON TABLE follow_up_tasks FROM goye_runtime;
DROP INDEX IF EXISTS follow_up_tasks_generated_from_task_unique;
ALTER TABLE follow_up_tasks
  DROP CONSTRAINT IF EXISTS follow_up_tasks_recurrence_interval_kind,
  DROP CONSTRAINT IF EXISTS follow_up_tasks_recurrence_interval_range,
  DROP COLUMN IF EXISTS generated_from_task_id,
  DROP COLUMN IF EXISTS recurrence_interval_days;

-- Preserve the privacy check while restoring the 0015 cadence assignment shape.
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

  INSERT INTO follow_up_tasks (
    convert_id, parish_id, task_type, cadence_step_id, occurrence_number, due_at
  )
  SELECT
    p_convert_id,
    p_parish_id,
    cadence.task_type,
    cadence.id,
    1,
    assignment_time + make_interval(hours => cadence.due_offset_hours)
  FROM follow_up_cadence_steps cadence
  WHERE cadence.is_active
  ON CONFLICT ON CONSTRAINT follow_up_tasks_convert_cadence_occurrence_unique DO NOTHING;

  RETURN QUERY SELECT p_convert_id, p_parish_id, assignment_time;
END;
$$;

REVOKE ALL ON FUNCTION goye_assign_convert_to_parish(uuid, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION goye_assign_convert_to_parish(uuid, uuid, uuid) TO goye_runtime;
