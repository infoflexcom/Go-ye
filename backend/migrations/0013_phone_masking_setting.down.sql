-- Roll back server-enforced phone masking configuration.
DROP TABLE IF EXISTS tenant_settings;
DROP FUNCTION IF EXISTS goye_prepare_tenant_settings_update();
