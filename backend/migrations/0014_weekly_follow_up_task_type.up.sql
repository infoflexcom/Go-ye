-- Phase 4 follow-up cadence adds a recurring weekly check-in task kind.
-- Rollback note: PostgreSQL enum labels cannot be removed safely; 0015 removes all
-- schema use of this label, while this label remains inert on a logical rollback.

ALTER TYPE follow_up_task_type ADD VALUE IF NOT EXISTS 'WEEKLY_CHECK_IN';
