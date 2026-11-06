-- Server-enforced phone masking configuration. Rollback: run 0013_phone_masking_setting.down.sql.

CREATE TABLE tenant_settings (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  mask_phone_numbers_above_parish boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO tenant_settings (singleton, mask_phone_numbers_above_parish) VALUES (true, false);

CREATE OR REPLACE FUNCTION goye_prepare_tenant_settings_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.singleton := true;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;
CREATE TRIGGER tenant_settings_prepare_before_update
BEFORE UPDATE ON tenant_settings
FOR EACH ROW EXECUTE FUNCTION goye_prepare_tenant_settings_update();

GRANT SELECT, UPDATE ON TABLE tenant_settings TO goye_runtime;
ALTER TABLE tenant_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_settings FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_settings_select_authenticated ON tenant_settings FOR SELECT
  USING (true);
CREATE POLICY tenant_settings_update_global ON tenant_settings FOR UPDATE
  USING (goye_is_system_actor() OR goye_is_global_admin())
  WITH CHECK (goye_is_system_actor() OR goye_is_global_admin());
