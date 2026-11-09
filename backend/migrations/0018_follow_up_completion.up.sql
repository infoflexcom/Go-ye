-- Phase 4 Today completion outcomes and encrypted notes.
-- Rollback: run 0018_follow_up_completion.down.sql before rolling back 0017.

CREATE TYPE follow_up_task_outcome AS ENUM (
  'COMPLETED',
  'NO_CONTACT',
  'RESCHEDULED',
  'DECLINED',
  'OTHER'
);

ALTER TABLE follow_up_tasks
  ADD COLUMN outcome follow_up_task_outcome,
  ADD COLUMN outcome_note_encrypted bytea,
  ADD COLUMN completed_by uuid REFERENCES users(id) ON DELETE RESTRICT;

-- No pre-Phase-4 endpoint could complete a task. This conservative backfill
-- keeps a valid historical actor if an operator completed one directly.
UPDATE follow_up_tasks task
SET outcome = 'COMPLETED',
    completed_by = COALESCE(convert.assigned_by, convert.registered_by)
FROM converts convert
WHERE convert.id = task.convert_id
  AND task.status = 'COMPLETED';

ALTER TABLE follow_up_tasks
  DROP CONSTRAINT follow_up_tasks_completion_consistent,
  ADD CONSTRAINT follow_up_tasks_completion_consistent CHECK (
    (
      status = 'COMPLETED'
      AND completed_at IS NOT NULL
      AND completed_by IS NOT NULL
      AND outcome IS NOT NULL
    )
    OR (
      status <> 'COMPLETED'
      AND completed_at IS NULL
      AND completed_by IS NULL
      AND outcome IS NULL
      AND outcome_note_encrypted IS NULL
    )
  ),
  ADD CONSTRAINT follow_up_tasks_outcome_note_shape CHECK (
    outcome_note_encrypted IS NULL OR octet_length(outcome_note_encrypted) > 29
  );

CREATE INDEX follow_up_tasks_pending_parish_due_idx
  ON follow_up_tasks (parish_id, due_at, id)
  WHERE status = 'PENDING';

CREATE OR REPLACE FUNCTION goye_complete_follow_up_task(
  p_task_id uuid,
  p_completed_by uuid,
  p_outcome follow_up_task_outcome,
  p_outcome_note_encrypted bytea DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  task_convert_id uuid;
  task_parish_id uuid;
  task_type_value follow_up_task_type;
  task_occurrence_number integer;
  task_status follow_up_task_status;
  current_privacy_status convert_privacy_status;
  current_merged_into_id uuid;
  completion_time timestamptz := now();
BEGIN
  IF NOT goye_is_system_actor() AND p_completed_by IS DISTINCT FROM goye_actor_user_id() THEN
    RAISE EXCEPTION 'follow-up completion actor must match the active actor' USING ERRCODE = '42501';
  END IF;
  IF p_outcome IS NULL THEN
    RAISE EXCEPTION 'follow-up outcome is required' USING ERRCODE = '22023';
  END IF;
  IF p_outcome_note_encrypted IS NOT NULL AND octet_length(p_outcome_note_encrypted) <= 29 THEN
    RAISE EXCEPTION 'follow-up outcome note is invalid' USING ERRCODE = '22023';
  END IF;

  SELECT task.convert_id, task.parish_id, task.task_type, task.occurrence_number,
         task.status, convert.privacy_status, convert.merged_into_id
  INTO task_convert_id, task_parish_id, task_type_value, task_occurrence_number,
       task_status, current_privacy_status, current_merged_into_id
  FROM follow_up_tasks task
  JOIN converts convert ON convert.id = task.convert_id
  WHERE task.id = p_task_id
  FOR UPDATE OF task, convert;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'follow-up task not found in actor scope' USING ERRCODE = 'P0002';
  END IF;
  IF NOT goye_is_system_actor() AND NOT goye_is_global_admin() AND NOT EXISTS (
    SELECT 1
    FROM org_units parish
    WHERE parish.id = task_parish_id
      AND goye_actor_home_path() IS NOT NULL
      AND parish.path <@ goye_actor_home_path()
  ) THEN
    RAISE EXCEPTION 'follow-up task not found in actor scope' USING ERRCODE = 'P0002';
  END IF;
  IF current_privacy_status <> 'ACTIVE' OR current_merged_into_id IS NOT NULL THEN
    RAISE EXCEPTION 'follow-up task is unavailable for a restricted convert' USING ERRCODE = '22023';
  END IF;
  IF task_status <> 'PENDING' THEN
    RAISE EXCEPTION 'follow-up task has already been resolved' USING ERRCODE = '22023';
  END IF;

  UPDATE follow_up_tasks
  SET status = 'COMPLETED',
      completed_at = completion_time,
      completed_by = p_completed_by,
      outcome = p_outcome,
      outcome_note_encrypted = p_outcome_note_encrypted
  WHERE id = p_task_id;

  INSERT INTO convert_timeline_events (
    convert_id, event_type, note_encrypted, actor_user_id, metadata
  ) VALUES (
    task_convert_id,
    'FOLLOW_UP_COMPLETED',
    p_outcome_note_encrypted,
    p_completed_by,
    jsonb_build_object(
      'taskId', p_task_id,
      'taskType', task_type_value::text,
      'occurrenceNumber', task_occurrence_number,
      'outcome', p_outcome::text
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION goye_complete_follow_up_task(uuid, uuid, follow_up_task_outcome, bytea) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION goye_complete_follow_up_task(uuid, uuid, follow_up_task_outcome, bytea) TO goye_runtime;
