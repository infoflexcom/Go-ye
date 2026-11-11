-- Roll back only the live escalation-list access path; no follow-up records are changed.
DROP INDEX IF EXISTS follow_up_tasks_pending_due_escalation_idx;
