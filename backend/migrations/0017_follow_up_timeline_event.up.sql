-- Phase 4 follow-up completion chronology label.
-- The label must be committed before a later migration can use it in a function.
ALTER TYPE convert_timeline_event_type ADD VALUE IF NOT EXISTS 'FOLLOW_UP_COMPLETED';
