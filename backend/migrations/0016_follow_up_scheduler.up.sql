-- Phase 4 durable follow-up scheduler and idempotent reminder queue.
-- Rollback: run 0016_follow_up_scheduler.down.sql before rolling back cadence configuration.

ALTER TABLE follow_up_tasks
  ADD COLUMN recurrence_interval_days integer,
  ADD COLUMN generated_from_task_id uuid REFERENCES follow_up_tasks(id) ON DELETE RESTRICT;

UPDATE follow_up_tasks task
SET recurrence_interval_days = cadence.recurrence_days
FROM follow_up_cadence_steps cadence
WHERE cadence.id = task.cadence_step_id
  AND cadence.recurrence_days IS NOT NULL;

ALTER TABLE follow_up_tasks
  ADD CONSTRAINT follow_up_tasks_recurrence_interval_range
    CHECK (recurrence_interval_days IS NULL OR recurrence_interval_days BETWEEN 1 AND 365),
  ADD CONSTRAINT follow_up_tasks_recurrence_interval_kind
    CHECK (
      (task_type = 'WEEKLY_CHECK_IN' AND recurrence_interval_days IS NOT NULL)
      OR (task_type <> 'WEEKLY_CHECK_IN' AND recurrence_interval_days IS NULL)
    );
CREATE UNIQUE INDEX follow_up_tasks_generated_from_task_unique
  ON follow_up_tasks (generated_from_task_id)
  WHERE generated_from_task_id IS NOT NULL;

-- RLS policies already limit non-system callers to their descendant Parish scope.
-- The scheduler operates as the system actor and needs to create its next occurrence.
GRANT INSERT, UPDATE ON TABLE follow_up_tasks TO goye_runtime;

CREATE TYPE follow_up_reminder_job_status AS ENUM (
  'PENDING',
  'PROCESSING',
  'DELIVERED',
  'CANCELLED',
  'DEAD_LETTER'
);

CREATE TABLE follow_up_reminder_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  follow_up_task_id uuid NOT NULL REFERENCES follow_up_tasks(id) ON DELETE RESTRICT,
  job_type text NOT NULL DEFAULT 'DUE_REMINDER',
  idempotency_key text NOT NULL UNIQUE,
  status follow_up_reminder_job_status NOT NULL DEFAULT 'PENDING',
  available_at timestamptz NOT NULL,
  attempts smallint NOT NULL DEFAULT 0,
  locked_by uuid,
  locked_at timestamptz,
  delivered_at timestamptz,
  last_error_code text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT follow_up_reminder_jobs_type CHECK (job_type = 'DUE_REMINDER'),
  CONSTRAINT follow_up_reminder_jobs_idempotency_key_format CHECK (
    idempotency_key ~ '^follow-up-task:[0-9a-f-]{36}:due-reminder$'
  ),
  CONSTRAINT follow_up_reminder_jobs_attempts_range CHECK (attempts BETWEEN 0 AND 8),
  CONSTRAINT follow_up_reminder_jobs_error_code_format CHECK (
    last_error_code IS NULL OR last_error_code ~ '^[A-Z][A-Z0-9_]{2,63}$'
  ),
  CONSTRAINT follow_up_reminder_jobs_delivery_state CHECK (
    (status = 'PENDING' AND locked_by IS NULL AND locked_at IS NULL AND delivered_at IS NULL)
    OR (status = 'PROCESSING' AND locked_by IS NOT NULL AND locked_at IS NOT NULL AND delivered_at IS NULL)
    OR (status = 'DELIVERED' AND locked_by IS NULL AND locked_at IS NULL AND delivered_at IS NOT NULL)
    OR (status IN ('CANCELLED', 'DEAD_LETTER') AND locked_by IS NULL AND locked_at IS NULL AND delivered_at IS NULL)
  ),
  CONSTRAINT follow_up_reminder_jobs_task_type_unique UNIQUE (follow_up_task_id, job_type)
);
CREATE INDEX follow_up_reminder_jobs_pending_available_idx
  ON follow_up_reminder_jobs (available_at, created_at)
  WHERE status = 'PENDING';
CREATE INDEX follow_up_reminder_jobs_task_idx ON follow_up_reminder_jobs (follow_up_task_id);

GRANT SELECT, INSERT, UPDATE ON TABLE follow_up_reminder_jobs TO goye_runtime;
ALTER TABLE follow_up_reminder_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE follow_up_reminder_jobs FORCE ROW LEVEL SECURITY;
CREATE POLICY follow_up_reminder_jobs_system_only ON follow_up_reminder_jobs
  FOR ALL
  USING (goye_is_system_actor())
  WITH CHECK (goye_is_system_actor());

CREATE OR REPLACE FUNCTION goye_claim_follow_up_reminder_jobs(
  p_worker_id uuid,
  p_limit integer,
  p_now timestamptz
)
RETURNS TABLE (
  id uuid,
  follow_up_task_id uuid,
  idempotency_key text,
  attempts smallint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT goye_is_system_actor() THEN
    RAISE EXCEPTION 'follow-up reminder jobs require a system actor' USING ERRCODE = '42501';
  END IF;
  IF p_worker_id IS NULL OR p_limit IS NULL OR p_limit < 1 OR p_limit > 100 THEN
    RAISE EXCEPTION 'worker and claim limit are invalid' USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  WITH candidates AS (
    SELECT job.id
    FROM follow_up_reminder_jobs job
    WHERE (
      job.status = 'PENDING'
      AND job.available_at <= p_now
      AND job.attempts < 8
    ) OR (
      job.status = 'PROCESSING'
      AND job.locked_at < p_now - interval '5 minutes'
      AND job.attempts < 8
    )
    ORDER BY job.available_at, job.created_at, job.id
    LIMIT p_limit
    FOR UPDATE SKIP LOCKED
  ), claimed AS (
    UPDATE follow_up_reminder_jobs job
    SET status = 'PROCESSING',
        locked_by = p_worker_id,
        locked_at = p_now,
        attempts = job.attempts + 1,
        updated_at = p_now
    FROM candidates
    WHERE job.id = candidates.id
    RETURNING job.id, job.follow_up_task_id, job.idempotency_key, job.attempts
  )
  SELECT claimed.id, claimed.follow_up_task_id, claimed.idempotency_key, claimed.attempts
  FROM claimed;
END;
$$;

CREATE OR REPLACE FUNCTION goye_mark_follow_up_reminder_job_delivered(
  p_job_id uuid,
  p_worker_id uuid,
  p_delivered_at timestamptz
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT goye_is_system_actor() THEN
    RAISE EXCEPTION 'follow-up reminder jobs require a system actor' USING ERRCODE = '42501';
  END IF;

  UPDATE follow_up_reminder_jobs
  SET status = 'DELIVERED',
      locked_by = NULL,
      locked_at = NULL,
      delivered_at = p_delivered_at,
      updated_at = p_delivered_at
  WHERE id = p_job_id
    AND status = 'PROCESSING'
    AND locked_by = p_worker_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'reminder job is not claimed by this worker' USING ERRCODE = '22023';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION goye_retry_follow_up_reminder_job(
  p_job_id uuid,
  p_worker_id uuid,
  p_error_code text,
  p_available_at timestamptz,
  p_updated_at timestamptz
)
RETURNS follow_up_reminder_job_status
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  resulting_status follow_up_reminder_job_status;
BEGIN
  IF NOT goye_is_system_actor() THEN
    RAISE EXCEPTION 'follow-up reminder jobs require a system actor' USING ERRCODE = '42501';
  END IF;
  IF p_error_code IS NULL OR p_error_code !~ '^[A-Z][A-Z0-9_]{2,63}$' THEN
    RAISE EXCEPTION 'reminder error code is invalid' USING ERRCODE = '22023';
  END IF;

  UPDATE follow_up_reminder_jobs
  SET status = CASE WHEN attempts >= 8 THEN 'DEAD_LETTER'::follow_up_reminder_job_status
                    ELSE 'PENDING'::follow_up_reminder_job_status END,
      available_at = CASE WHEN attempts >= 8 THEN available_at ELSE p_available_at END,
      locked_by = NULL,
      locked_at = NULL,
      last_error_code = p_error_code,
      updated_at = p_updated_at
  WHERE id = p_job_id
    AND status = 'PROCESSING'
    AND locked_by = p_worker_id
  RETURNING status INTO resulting_status;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'reminder job is not claimed by this worker' USING ERRCODE = '22023';
  END IF;
  RETURN resulting_status;
END;
$$;

REVOKE ALL ON FUNCTION goye_claim_follow_up_reminder_jobs(uuid, integer, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION goye_claim_follow_up_reminder_jobs(uuid, integer, timestamptz) TO goye_runtime;
REVOKE ALL ON FUNCTION goye_mark_follow_up_reminder_job_delivered(uuid, uuid, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION goye_mark_follow_up_reminder_job_delivered(uuid, uuid, timestamptz) TO goye_runtime;
REVOKE ALL ON FUNCTION goye_retry_follow_up_reminder_job(uuid, uuid, text, timestamptz, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION goye_retry_follow_up_reminder_job(uuid, uuid, text, timestamptz, timestamptz) TO goye_runtime;

-- Snapshot recurrence settings on assignment. Existing queued journeys keep their
-- original interval even if Global Admin later adjusts the cadence configuration.
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
    convert_id, parish_id, task_type, cadence_step_id, occurrence_number,
    recurrence_interval_days, due_at
  )
  SELECT
    p_convert_id,
    p_parish_id,
    cadence.task_type,
    cadence.id,
    1,
    cadence.recurrence_days,
    assignment_time + make_interval(hours => cadence.due_offset_hours)
  FROM follow_up_cadence_steps cadence
  WHERE cadence.is_active
  ON CONFLICT ON CONSTRAINT follow_up_tasks_convert_cadence_occurrence_unique DO NOTHING;

  RETURN QUERY SELECT p_convert_id, p_parish_id, assignment_time;
END;
$$;

REVOKE ALL ON FUNCTION goye_assign_convert_to_parish(uuid, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION goye_assign_convert_to_parish(uuid, uuid, uuid) TO goye_runtime;
