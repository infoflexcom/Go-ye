-- Phase 2 stage pipeline and append-only convert activity timeline.
-- Rollback: run 0010_convert_stages_and_timeline.down.sql before rolling back duplicate merge.

CREATE TYPE convert_stage AS ENUM (
  'NEW_CONVERT',
  'BELIEVERS_CLASS',
  'BAPTISMAL_CLASS',
  'BAPTISED',
  'FULLY_PLANTED'
);
CREATE TYPE convert_timeline_event_type AS ENUM (
  'REGISTERED',
  'PARISH_ASSIGNED',
  'STAGE_ADVANCED',
  'NOTE',
  'MERGED_INTO',
  'MERGED_DUPLICATE'
);

ALTER TABLE converts
  ADD COLUMN stage convert_stage NOT NULL DEFAULT 'NEW_CONVERT',
  ADD COLUMN stage_changed_at timestamptz NOT NULL DEFAULT now();
CREATE INDEX converts_active_stage_registered_idx
  ON converts (registered_at_unit_id, stage, created_at DESC) WHERE merged_into_id IS NULL;
CREATE INDEX converts_active_parish_stage_idx
  ON converts (parish_id, stage, created_at DESC) WHERE merged_into_id IS NULL AND parish_id IS NOT NULL;

CREATE TABLE convert_timeline_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_sequence bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
  convert_id uuid NOT NULL REFERENCES converts(id) ON DELETE RESTRICT,
  event_type convert_timeline_event_type NOT NULL,
  from_stage convert_stage,
  to_stage convert_stage,
  note_encrypted bytea,
  actor_user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT convert_timeline_stage_transition_shape CHECK (
    (event_type = 'STAGE_ADVANCED' AND from_stage IS NOT NULL AND to_stage IS NOT NULL)
    OR (event_type <> 'STAGE_ADVANCED' AND from_stage IS NULL AND to_stage IS NULL)
  ),
  CONSTRAINT convert_timeline_note_shape CHECK (
    note_encrypted IS NULL OR octet_length(note_encrypted) > 29
  )
);
CREATE INDEX convert_timeline_events_convert_sequence_idx
  ON convert_timeline_events (convert_id, event_sequence);

CREATE OR REPLACE FUNCTION goye_reject_convert_timeline_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'convert timeline is append-only' USING ERRCODE = '55000';
END;
$$;
CREATE TRIGGER convert_timeline_events_append_only
BEFORE UPDATE OR DELETE ON convert_timeline_events
FOR EACH ROW EXECUTE FUNCTION goye_reject_convert_timeline_mutation();

GRANT SELECT ON TABLE convert_timeline_events TO goye_runtime;
ALTER TABLE convert_timeline_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE convert_timeline_events FORCE ROW LEVEL SECURITY;
CREATE POLICY convert_timeline_events_select_scope ON convert_timeline_events FOR SELECT
  USING (EXISTS (SELECT 1 FROM converts c WHERE c.id = convert_timeline_events.convert_id));
CREATE POLICY convert_timeline_events_insert_scope ON convert_timeline_events FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM converts c WHERE c.id = convert_timeline_events.convert_id));

CREATE OR REPLACE FUNCTION goye_convert_stage_rank(p_stage convert_stage)
RETURNS integer
LANGUAGE sql
IMMUTABLE
STRICT
AS $$
  SELECT CASE p_stage
    WHEN 'NEW_CONVERT' THEN 1
    WHEN 'BELIEVERS_CLASS' THEN 2
    WHEN 'BAPTISMAL_CLASS' THEN 3
    WHEN 'BAPTISED' THEN 4
    WHEN 'FULLY_PLANTED' THEN 5
  END;
$$;

CREATE OR REPLACE FUNCTION goye_append_convert_timeline_event(
  p_convert_id uuid,
  p_event_type convert_timeline_event_type,
  p_actor_user_id uuid,
  p_note_encrypted bytea DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  event_id uuid;
BEGIN
  IF NOT goye_is_system_actor() AND p_actor_user_id IS DISTINCT FROM goye_actor_user_id() THEN
    RAISE EXCEPTION 'timeline actor must match the active actor' USING ERRCODE = '42501';
  END IF;
  PERFORM 1 FROM converts WHERE id = p_convert_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'convert not found in actor scope' USING ERRCODE = 'P0002';
  END IF;
  INSERT INTO convert_timeline_events (convert_id, event_type, actor_user_id, note_encrypted, metadata)
  VALUES (p_convert_id, p_event_type, p_actor_user_id, p_note_encrypted, COALESCE(p_metadata, '{}'::jsonb))
  RETURNING id INTO event_id;
  RETURN event_id;
END;
$$;

CREATE OR REPLACE FUNCTION goye_advance_convert_stage(
  p_convert_id uuid,
  p_target_stage convert_stage,
  p_actor_user_id uuid,
  p_note_encrypted bytea DEFAULT NULL
)
RETURNS TABLE (
  convert_id uuid,
  previous_stage convert_stage,
  current_stage convert_stage,
  stage_changed_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  old_stage convert_stage;
  assigned_parish_id uuid;
  changed_at timestamptz := now();
BEGIN
  IF NOT goye_is_system_actor() AND p_actor_user_id IS DISTINCT FROM goye_actor_user_id() THEN
    RAISE EXCEPTION 'stage actor must match the active actor' USING ERRCODE = '42501';
  END IF;
  SELECT stage, parish_id INTO old_stage, assigned_parish_id
  FROM converts
  WHERE id = p_convert_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'convert not found in actor scope' USING ERRCODE = 'P0002';
  END IF;
  IF assigned_parish_id IS NULL THEN
    RAISE EXCEPTION 'a convert must be assigned to a parish before advancing stages' USING ERRCODE = '22023';
  END IF;
  IF goye_convert_stage_rank(p_target_stage) <> goye_convert_stage_rank(old_stage) + 1 THEN
    RAISE EXCEPTION 'stage transitions must advance exactly one configured step' USING ERRCODE = '22023';
  END IF;

  UPDATE converts
  SET stage = p_target_stage, stage_changed_at = changed_at
  WHERE id = p_convert_id;
  INSERT INTO convert_timeline_events (
    convert_id, event_type, from_stage, to_stage, note_encrypted, actor_user_id
  ) VALUES (
    p_convert_id, 'STAGE_ADVANCED', old_stage, p_target_stage, p_note_encrypted, p_actor_user_id
  );
  RETURN QUERY SELECT p_convert_id, old_stage, p_target_stage, changed_at;
END;
$$;

REVOKE ALL ON FUNCTION goye_append_convert_timeline_event(uuid, convert_timeline_event_type, uuid, bytea, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION goye_append_convert_timeline_event(uuid, convert_timeline_event_type, uuid, bytea, jsonb) TO goye_runtime;
REVOKE ALL ON FUNCTION goye_advance_convert_stage(uuid, convert_stage, uuid, bytea) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION goye_advance_convert_stage(uuid, convert_stage, uuid, bytea) TO goye_runtime;
