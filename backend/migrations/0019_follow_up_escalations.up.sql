-- Phase 4 live overdue escalation and neglected-convert list support.
-- Rollback: run 0019_follow_up_escalations.down.sql; no journey data is changed.
--
-- Escalation and neglect are derived from the authoritative pending-task state,
-- rather than written as mutable rows. This prevents duplicate escalations when
-- the scheduler retries and makes completion immediately remove a resolved item.

CREATE INDEX follow_up_tasks_pending_due_escalation_idx
  ON follow_up_tasks (due_at, parish_id, convert_id, id)
  WHERE status = 'PENDING';
