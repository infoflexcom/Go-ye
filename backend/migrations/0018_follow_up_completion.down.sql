-- Roll back completion fields/function before rolling back the timeline event label.
-- The FOLLOW_UP_COMPLETED enum value added by 0017 intentionally remains.

REVOKE ALL ON FUNCTION goye_complete_follow_up_task(uuid, uuid, follow_up_task_outcome, bytea) FROM goye_runtime;
DROP FUNCTION IF EXISTS goye_complete_follow_up_task(uuid, uuid, follow_up_task_outcome, bytea);

DROP INDEX IF EXISTS follow_up_tasks_pending_parish_due_idx;
ALTER TABLE follow_up_tasks
  DROP CONSTRAINT IF EXISTS follow_up_tasks_outcome_note_shape,
  DROP CONSTRAINT IF EXISTS follow_up_tasks_completion_consistent,
  ADD CONSTRAINT follow_up_tasks_completion_consistent CHECK (
    (status = 'COMPLETED' AND completed_at IS NOT NULL)
    OR (status <> 'COMPLETED' AND completed_at IS NULL)
  ),
  DROP COLUMN IF EXISTS completed_by,
  DROP COLUMN IF EXISTS outcome_note_encrypted,
  DROP COLUMN IF EXISTS outcome;
DROP TYPE IF EXISTS follow_up_task_outcome;
