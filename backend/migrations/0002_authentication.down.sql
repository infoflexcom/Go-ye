DROP TABLE IF EXISTS auth_lockouts;
DROP FUNCTION IF EXISTS goye_append_audit_event(uuid, text, text, uuid, uuid, jsonb);
DROP TABLE IF EXISTS otp_challenges;
DROP TYPE IF EXISTS otp_channel;
