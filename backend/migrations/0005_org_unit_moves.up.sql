-- Managed subtree moves preserve stable UUID labels while rebuilding every affected ltree path.
-- Rollback: restores the pre-move trigger guard and drops the procedure.

CREATE OR REPLACE FUNCTION goye_prepare_org_unit()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  parent_type org_unit_type;
  parent_path ltree;
  parent_active boolean;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.type <> OLD.type THEN
      RAISE EXCEPTION 'org unit type is immutable' USING ERRCODE = '22023';
    END IF;
    IF NEW.parent_id IS DISTINCT FROM OLD.parent_id
      AND NOT goye_setting_is_true('goye.allow_org_move') THEN
      RAISE EXCEPTION 'use move_org_unit to change a parent' USING ERRCODE = '22023';
    END IF;
    IF NEW.path <> OLD.path AND NOT goye_setting_is_true('goye.allow_org_move') THEN
      RAISE EXCEPTION 'org unit path is managed by the database' USING ERRCODE = '22023';
    END IF;
    NEW.updated_at := now();
    IF NEW.is_active AND NOT OLD.is_active THEN
      NEW.deactivated_at := NULL;
    ELSIF NOT NEW.is_active AND OLD.is_active THEN
      NEW.deactivated_at := now();
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.parent_id IS NULL THEN
    IF NEW.type <> 'COUNTRY' THEN
      RAISE EXCEPTION 'only COUNTRY can be a root org unit' USING ERRCODE = '23514';
    END IF;
    NEW.path := goye_unit_label(NEW.id);
    RETURN NEW;
  END IF;

  SELECT type, path, is_active INTO parent_type, parent_path, parent_active
  FROM org_units
  WHERE id = NEW.parent_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'parent org unit does not exist' USING ERRCODE = '23503';
  END IF;
  IF NOT parent_active THEN
    RAISE EXCEPTION 'cannot create a child under an inactive org unit' USING ERRCODE = '23514';
  END IF;
  IF parent_type <> goye_expected_parent_type(NEW.type) THEN
    RAISE EXCEPTION 'invalid parent type % for child type %', parent_type, NEW.type
      USING ERRCODE = '23514';
  END IF;

  NEW.path := parent_path || goye_unit_label(NEW.id);
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION goye_move_org_unit(p_unit_id uuid, p_new_parent_id uuid)
RETURNS TABLE (unit_id uuid, old_path text, new_path text, moved_descendant_count integer)
LANGUAGE plpgsql
AS $$
DECLARE
  source_type org_unit_type;
  source_path ltree;
  destination_type org_unit_type;
  destination_path ltree;
  destination_active boolean;
  replacement_path ltree;
  descendant_count integer;
BEGIN
  SELECT type, path INTO source_type, source_path
  FROM org_units WHERE id = p_unit_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'org unit not found' USING ERRCODE = 'P0002';
  END IF;
  IF p_unit_id = p_new_parent_id THEN
    RAISE EXCEPTION 'an org unit cannot parent itself' USING ERRCODE = '22023';
  END IF;

  SELECT type, path, is_active INTO destination_type, destination_path, destination_active
  FROM org_units WHERE id = p_new_parent_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'new parent org unit not found' USING ERRCODE = 'P0002';
  END IF;
  IF NOT destination_active THEN
    RAISE EXCEPTION 'cannot move under an inactive org unit' USING ERRCODE = '23514';
  END IF;
  IF destination_type <> goye_expected_parent_type(source_type) THEN
    RAISE EXCEPTION 'invalid parent type % for child type %', destination_type, source_type
      USING ERRCODE = '23514';
  END IF;
  IF destination_path <@ source_path THEN
    RAISE EXCEPTION 'cannot move an org unit under itself or a descendant' USING ERRCODE = '22023';
  END IF;

  replacement_path := destination_path || goye_unit_label(p_unit_id);
  SELECT count(*)::integer INTO descendant_count FROM org_units WHERE path <@ source_path;
  PERFORM set_config('goye.allow_org_move', 'true', true);

  UPDATE org_units SET parent_id = p_new_parent_id WHERE id = p_unit_id;
  UPDATE org_units
  SET path = CASE
    WHEN path = source_path THEN replacement_path
    ELSE replacement_path || subpath(path, nlevel(source_path))
  END
  WHERE path <@ source_path;

  RETURN QUERY SELECT p_unit_id, source_path::text, replacement_path::text, descendant_count;
END;
$$;

GRANT EXECUTE ON FUNCTION goye_move_org_unit(uuid, uuid) TO goye_runtime;
