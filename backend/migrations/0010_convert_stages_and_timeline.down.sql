-- Roll back stage pipeline and timeline.
REVOKE EXECUTE ON FUNCTION goye_advance_convert_stage(uuid, convert_stage, uuid, bytea) FROM goye_runtime;
REVOKE EXECUTE ON FUNCTION goye_append_convert_timeline_event(uuid, convert_timeline_event_type, uuid, bytea, jsonb) FROM goye_runtime;
DROP FUNCTION IF EXISTS goye_advance_convert_stage(uuid, convert_stage, uuid, bytea);
DROP FUNCTION IF EXISTS goye_append_convert_timeline_event(uuid, convert_timeline_event_type, uuid, bytea, jsonb);
DROP FUNCTION IF EXISTS goye_convert_stage_rank(convert_stage);
DROP TABLE IF EXISTS convert_timeline_events;
DROP FUNCTION IF EXISTS goye_reject_convert_timeline_mutation();
ALTER TABLE converts
  DROP COLUMN IF EXISTS stage_changed_at,
  DROP COLUMN IF EXISTS stage;
DROP TYPE IF EXISTS convert_timeline_event_type;
DROP TYPE IF EXISTS convert_stage;
