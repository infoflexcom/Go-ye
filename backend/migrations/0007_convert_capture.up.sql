-- Phase 2 convert capture foundation.
-- Rollback: run 0007_convert_capture.down.sql before later convert workflow migrations.

CREATE TYPE consent_capture_method AS ENUM ('VERBAL', 'DIGITAL', 'WRITTEN');

CREATE TABLE converts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name_encrypted bytea NOT NULL,
  phone_encrypted bytea,
  address_encrypted bytea,
  registered_at_unit_id uuid NOT NULL REFERENCES org_units(id) ON DELETE RESTRICT,
  registered_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  parish_id uuid REFERENCES org_units(id) ON DELETE RESTRICT,
  consent_granted boolean NOT NULL,
  consent_version text NOT NULL,
  consent_method consent_capture_method NOT NULL,
  consent_captured_at timestamptz NOT NULL DEFAULT now(),
  consent_captured_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT converts_consent_mandatory CHECK (consent_granted),
  CONSTRAINT converts_consent_version_not_blank CHECK (length(btrim(consent_version)) > 0),
  CONSTRAINT converts_encrypted_name_not_empty CHECK (octet_length(full_name_encrypted) > 29),
  CONSTRAINT converts_encrypted_phone_not_empty CHECK (
    phone_encrypted IS NULL OR octet_length(phone_encrypted) > 29
  ),
  CONSTRAINT converts_encrypted_address_not_empty CHECK (
    address_encrypted IS NULL OR octet_length(address_encrypted) > 29
  )
);

CREATE INDEX converts_registered_unit_created_idx ON converts (registered_at_unit_id, created_at DESC);
CREATE INDEX converts_parish_created_idx ON converts (parish_id, created_at DESC) WHERE parish_id IS NOT NULL;
CREATE INDEX converts_registered_by_created_idx ON converts (registered_by, created_at DESC);

CREATE OR REPLACE FUNCTION goye_prepare_convert_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.registered_at_unit_id <> OLD.registered_at_unit_id
     OR NEW.registered_by <> OLD.registered_by THEN
    RAISE EXCEPTION 'convert registration origin is immutable' USING ERRCODE = '22023';
  END IF;
  IF NEW.consent_granted <> OLD.consent_granted
     OR NEW.consent_version <> OLD.consent_version
     OR NEW.consent_method <> OLD.consent_method
     OR NEW.consent_captured_at <> OLD.consent_captured_at
     OR NEW.consent_captured_by <> OLD.consent_captured_by THEN
    RAISE EXCEPTION 'captured consent is immutable' USING ERRCODE = '22023';
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER converts_prepare_before_update
BEFORE UPDATE ON converts
FOR EACH ROW EXECUTE FUNCTION goye_prepare_convert_update();

GRANT SELECT, INSERT, UPDATE ON TABLE converts TO goye_runtime;

ALTER TABLE converts ENABLE ROW LEVEL SECURITY;
ALTER TABLE converts FORCE ROW LEVEL SECURITY;
CREATE POLICY converts_select_scope ON converts FOR SELECT
  USING (
    goye_is_system_actor()
    OR goye_is_global_admin()
    OR EXISTS (
      SELECT 1 FROM org_units registered_unit
      WHERE registered_unit.id = converts.registered_at_unit_id
      AND goye_actor_home_path() IS NOT NULL
      AND registered_unit.path <@ goye_actor_home_path()
    )
    OR EXISTS (
      SELECT 1 FROM org_units assigned_parish
      WHERE assigned_parish.id = converts.parish_id
      AND goye_actor_home_path() IS NOT NULL
      AND assigned_parish.path <@ goye_actor_home_path()
    )
  );
CREATE POLICY converts_insert_own_scoped_registration ON converts FOR INSERT
  WITH CHECK (
    goye_is_system_actor()
    OR goye_is_global_admin()
    OR (
      registered_by = goye_actor_user_id()
      AND consent_captured_by = goye_actor_user_id()
      AND EXISTS (
        SELECT 1 FROM org_units registered_unit
        WHERE registered_unit.id = converts.registered_at_unit_id
        AND goye_actor_home_path() IS NOT NULL
        AND registered_unit.path <@ goye_actor_home_path()
      )
    )
  );
CREATE POLICY converts_update_scope ON converts FOR UPDATE
  USING (
    goye_is_system_actor()
    OR goye_is_global_admin()
    OR EXISTS (
      SELECT 1 FROM org_units registered_unit
      WHERE registered_unit.id = converts.registered_at_unit_id
      AND goye_actor_home_path() IS NOT NULL
      AND registered_unit.path <@ goye_actor_home_path()
    )
    OR EXISTS (
      SELECT 1 FROM org_units assigned_parish
      WHERE assigned_parish.id = converts.parish_id
      AND goye_actor_home_path() IS NOT NULL
      AND assigned_parish.path <@ goye_actor_home_path()
    )
  )
  WITH CHECK (
    goye_is_system_actor()
    OR goye_is_global_admin()
    OR EXISTS (
      SELECT 1 FROM org_units registered_unit
      WHERE registered_unit.id = converts.registered_at_unit_id
      AND goye_actor_home_path() IS NOT NULL
      AND registered_unit.path <@ goye_actor_home_path()
    )
    OR EXISTS (
      SELECT 1 FROM org_units assigned_parish
      WHERE assigned_parish.id = converts.parish_id
      AND goye_actor_home_path() IS NOT NULL
      AND assigned_parish.path <@ goye_actor_home_path()
    )
  );
