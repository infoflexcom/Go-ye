-- Phase 2 current-stage daily hierarchy roll-up summaries.
-- Rollback: run 0011_convert_rollups.down.sql before rolling back stages.

CREATE TABLE convert_rollup_daily (
  report_date date NOT NULL,
  org_unit_id uuid NOT NULL REFERENCES org_units(id) ON DELETE RESTRICT,
  stage convert_stage NOT NULL,
  total_count bigint NOT NULL CHECK (total_count >= 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (report_date, org_unit_id, stage)
);
CREATE INDEX convert_rollup_daily_unit_date_idx
  ON convert_rollup_daily (org_unit_id, report_date, stage);

CREATE OR REPLACE FUNCTION goye_apply_convert_rollup(
  p_counted_at_unit_id uuid,
  p_report_date date,
  p_stage convert_stage,
  p_delta bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_delta = 0 THEN
    RETURN;
  END IF;

  IF p_delta > 0 THEN
    INSERT INTO convert_rollup_daily (report_date, org_unit_id, stage, total_count, updated_at)
    SELECT p_report_date, ancestor.id, p_stage, p_delta, now()
    FROM org_units counted_unit
    JOIN org_units ancestor ON counted_unit.path <@ ancestor.path
    WHERE counted_unit.id = p_counted_at_unit_id
    ON CONFLICT (report_date, org_unit_id, stage) DO UPDATE
    SET total_count = convert_rollup_daily.total_count + EXCLUDED.total_count,
        updated_at = now();
  ELSE
    UPDATE convert_rollup_daily summary
    SET total_count = summary.total_count + p_delta,
        updated_at = now()
    WHERE summary.report_date = p_report_date
      AND summary.stage = p_stage
      AND summary.org_unit_id IN (
        SELECT ancestor.id
        FROM org_units counted_unit
        JOIN org_units ancestor ON counted_unit.path <@ ancestor.path
        WHERE counted_unit.id = p_counted_at_unit_id
      );
    IF NOT FOUND THEN
      RAISE EXCEPTION 'roll-up decrement has no matching summary row' USING ERRCODE = '23514';
    END IF;
  END IF;

  DELETE FROM convert_rollup_daily
  WHERE report_date = p_report_date
    AND stage = p_stage
    AND org_unit_id IN (
      SELECT ancestor.id
      FROM org_units counted_unit
      JOIN org_units ancestor ON counted_unit.path <@ ancestor.path
      WHERE counted_unit.id = p_counted_at_unit_id
    )
    AND total_count = 0;
END;
$$;

CREATE OR REPLACE FUNCTION goye_maintain_convert_rollup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  old_counted_unit_id uuid;
  new_counted_unit_id uuid;
  old_counted boolean;
  new_counted boolean;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.merged_into_id IS NULL THEN
      PERFORM goye_apply_convert_rollup(
        COALESCE(NEW.parish_id, NEW.registered_at_unit_id),
        NEW.created_at::date,
        NEW.stage,
        1
      );
    END IF;
    RETURN NEW;
  END IF;

  old_counted := OLD.merged_into_id IS NULL;
  new_counted := NEW.merged_into_id IS NULL;
  old_counted_unit_id := COALESCE(OLD.parish_id, OLD.registered_at_unit_id);
  new_counted_unit_id := COALESCE(NEW.parish_id, NEW.registered_at_unit_id);

  IF old_counted AND (
    NOT new_counted
    OR old_counted_unit_id IS DISTINCT FROM new_counted_unit_id
    OR OLD.created_at::date IS DISTINCT FROM NEW.created_at::date
    OR OLD.stage IS DISTINCT FROM NEW.stage
  ) THEN
    PERFORM goye_apply_convert_rollup(old_counted_unit_id, OLD.created_at::date, OLD.stage, -1);
  END IF;

  IF new_counted AND (
    NOT old_counted
    OR old_counted_unit_id IS DISTINCT FROM new_counted_unit_id
    OR OLD.created_at::date IS DISTINCT FROM NEW.created_at::date
    OR OLD.stage IS DISTINCT FROM NEW.stage
  ) THEN
    PERFORM goye_apply_convert_rollup(new_counted_unit_id, NEW.created_at::date, NEW.stage, 1);
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER converts_maintain_rollup_after_write
AFTER INSERT OR UPDATE OF registered_at_unit_id, parish_id, created_at, stage, merged_into_id ON converts
FOR EACH ROW EXECUTE FUNCTION goye_maintain_convert_rollup();

-- Build a correct summary for any rows already present before the trigger is installed.
INSERT INTO convert_rollup_daily (report_date, org_unit_id, stage, total_count)
SELECT c.created_at::date, ancestor.id, c.stage, count(*)::bigint
FROM converts c
JOIN org_units counted_unit ON counted_unit.id = COALESCE(c.parish_id, c.registered_at_unit_id)
JOIN org_units ancestor ON counted_unit.path <@ ancestor.path
WHERE c.merged_into_id IS NULL
GROUP BY c.created_at::date, ancestor.id, c.stage;

GRANT SELECT ON TABLE convert_rollup_daily TO goye_runtime;
ALTER TABLE convert_rollup_daily ENABLE ROW LEVEL SECURITY;
ALTER TABLE convert_rollup_daily FORCE ROW LEVEL SECURITY;
CREATE POLICY convert_rollup_daily_select_scope ON convert_rollup_daily FOR SELECT
  USING (
    goye_is_system_actor()
    OR goye_is_global_admin()
    OR EXISTS (
      SELECT 1 FROM org_units unit
      WHERE unit.id = convert_rollup_daily.org_unit_id
      AND goye_actor_home_path() IS NOT NULL
      AND unit.path <@ goye_actor_home_path()
    )
  );
CREATE POLICY convert_rollup_daily_maintainer ON convert_rollup_daily FOR ALL
  USING (
    current_user = (
      SELECT pg_get_userbyid(proowner)
      FROM pg_proc
      WHERE oid = 'goye_apply_convert_rollup(uuid,date,convert_stage,bigint)'::regprocedure
    )
  )
  WITH CHECK (
    current_user = (
      SELECT pg_get_userbyid(proowner)
      FROM pg_proc
      WHERE oid = 'goye_apply_convert_rollup(uuid,date,convert_stage,bigint)'::regprocedure
    )
  );

REVOKE ALL ON FUNCTION goye_apply_convert_rollup(uuid, date, convert_stage, bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION goye_maintain_convert_rollup() FROM PUBLIC;
