-- Phase 4 configurable follow-up cadence.
-- Rollback: run 0015_follow_up_cadence.down.sql before rolling back Phase 2 follow-up tables.

CREATE TABLE follow_up_cadence_steps (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  task_type follow_up_task_type NOT NULL UNIQUE,
  label text NOT NULL,
  due_offset_hours integer NOT NULL,
  recurrence_days integer,
  is_active boolean NOT NULL DEFAULT true,
  sort_order smallint NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT follow_up_cadence_steps_code_format CHECK (code ~ '^[A-Z][A-Z0-9_]{2,63}$'),
  CONSTRAINT follow_up_cadence_steps_label_not_blank CHECK (length(btrim(label)) > 0),
  CONSTRAINT follow_up_cadence_steps_due_offset_range CHECK (due_offset_hours BETWEEN 1 AND 8760),
  CONSTRAINT follow_up_cadence_steps_recurrence_range CHECK (
    recurrence_days IS NULL OR recurrence_days BETWEEN 1 AND 365
  ),
  CONSTRAINT follow_up_cadence_steps_recurrence_kind CHECK (
    (task_type = 'WEEKLY_CHECK_IN' AND recurrence_days IS NOT NULL)
    OR (task_type <> 'WEEKLY_CHECK_IN' AND recurrence_days IS NULL)
  )
);

-- A weekly check-in first falls one week after the Day-7 visit. The scheduler
-- added in the next task materialises later recurrence occurrences.
INSERT INTO follow_up_cadence_steps (
  code, task_type, label, due_offset_hours, recurrence_days, sort_order
) VALUES
  ('CALL_24H', 'CALL_24H', '24-hour call', 24, NULL, 10),
  ('PRAYER_DAY_3', 'PRAYER_DAY_3', 'Day 3 prayer', 72, NULL, 20),
  ('VISIT_DAY_7', 'VISIT_DAY_7', 'Day 7 visit', 168, NULL, 30),
  ('WEEKLY_CHECK_IN', 'WEEKLY_CHECK_IN', 'Weekly check-in', 336, 7, 40);

CREATE OR REPLACE FUNCTION goye_prepare_follow_up_cadence_step_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.code <> OLD.code OR NEW.task_type <> OLD.task_type OR NEW.sort_order <> OLD.sort_order THEN
    RAISE EXCEPTION 'cadence identity fields are immutable' USING ERRCODE = '22023';
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;
CREATE TRIGGER follow_up_cadence_steps_prepare_before_update
BEFORE UPDATE ON follow_up_cadence_steps
FOR EACH ROW EXECUTE FUNCTION goye_prepare_follow_up_cadence_step_update();

GRANT SELECT, UPDATE ON TABLE follow_up_cadence_steps TO goye_runtime;
ALTER TABLE follow_up_cadence_steps ENABLE ROW LEVEL SECURITY;
ALTER TABLE follow_up_cadence_steps FORCE ROW LEVEL SECURITY;
CREATE POLICY follow_up_cadence_steps_select_global ON follow_up_cadence_steps FOR SELECT
  USING (goye_is_system_actor() OR goye_is_global_admin());
CREATE POLICY follow_up_cadence_steps_update_global ON follow_up_cadence_steps FOR UPDATE
  USING (goye_is_system_actor() OR goye_is_global_admin())
  WITH CHECK (goye_is_system_actor() OR goye_is_global_admin());

ALTER TABLE follow_up_tasks
  ADD COLUMN cadence_step_id uuid REFERENCES follow_up_cadence_steps(id) ON DELETE RESTRICT,
  ADD COLUMN occurrence_number integer NOT NULL DEFAULT 1
    CHECK (occurrence_number > 0);

UPDATE follow_up_tasks task
SET cadence_step_id = cadence.id
FROM follow_up_cadence_steps cadence
WHERE cadence.task_type = task.task_type;

ALTER TABLE follow_up_tasks
  ALTER COLUMN cadence_step_id SET NOT NULL;
DROP INDEX follow_up_tasks_pending_convert_type_unique;
ALTER TABLE follow_up_tasks
  ADD CONSTRAINT follow_up_tasks_convert_cadence_occurrence_unique
    UNIQUE (convert_id, cadence_step_id, occurrence_number);
CREATE INDEX follow_up_tasks_pending_cadence_due_idx
  ON follow_up_tasks (cadence_step_id, due_at) WHERE status = 'PENDING';

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
