-- OTP authentication state. Secrets and plaintext OTPs are never persisted.
-- Rollback: run 0002_authentication.down.sql before rolling back 0001.

CREATE TYPE otp_channel AS ENUM ('PHONE', 'EMAIL');

CREATE TABLE otp_challenges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  channel otp_channel NOT NULL,
  destination_hash text NOT NULL,
  code_hash text NOT NULL,
  attempts integer NOT NULL DEFAULT 0,
  max_attempts integer NOT NULL DEFAULT 5,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz,
  locked_at timestamptz,
  request_ip_hash text,
  device_identifier_hash text,
  CONSTRAINT otp_challenges_expiry_after_create CHECK (expires_at > created_at),
  CONSTRAINT otp_challenges_attempts_nonnegative CHECK (attempts >= 0 AND max_attempts > 0)
);
CREATE INDEX otp_challenges_destination_created_idx ON otp_challenges (destination_hash, created_at DESC);
CREATE INDEX otp_challenges_ip_created_idx ON otp_challenges (request_ip_hash, created_at DESC);
CREATE INDEX otp_challenges_user_created_idx ON otp_challenges (user_id, created_at DESC);

CREATE TABLE auth_lockouts (
  destination_hash text PRIMARY KEY,
  locked_until timestamptz NOT NULL,
  failed_attempts integer NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT auth_lockouts_failed_attempts_positive CHECK (failed_attempts > 0)
);
CREATE INDEX auth_lockouts_locked_until_idx ON auth_lockouts (locked_until);

CREATE OR REPLACE FUNCTION goye_append_audit_event(
  p_actor_user_id uuid,
  p_action text,
  p_resource_type text,
  p_resource_id uuid,
  p_scope_unit_id uuid,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  chain_previous_hash text;
  chain_entry_hash text;
  audit_id uuid;
  audit_secret text;
  canonical_payload text;
BEGIN
  audit_secret := current_setting('goye.audit_secret', true);
  IF audit_secret IS NULL OR length(audit_secret) < 32 THEN
    RAISE EXCEPTION 'audit secret is not configured for this transaction' USING ERRCODE = '28000';
  END IF;

  SELECT latest_hash INTO chain_previous_hash
  FROM audit_chain_state
  WHERE singleton = true
  FOR UPDATE;

  canonical_payload := concat_ws('|',
    chain_previous_hash,
    COALESCE(p_actor_user_id::text, ''),
    p_action,
    p_resource_type,
    COALESCE(p_resource_id::text, ''),
    COALESCE(p_scope_unit_id::text, ''),
    p_metadata::text
  );
  chain_entry_hash := encode(hmac(canonical_payload, audit_secret, 'sha256'), 'hex');

  INSERT INTO audit_log (
    actor_user_id, action, resource_type, resource_id, scope_unit_id, metadata, previous_hash, entry_hash
  ) VALUES (
    p_actor_user_id, p_action, p_resource_type, p_resource_id, p_scope_unit_id, p_metadata,
    chain_previous_hash, chain_entry_hash
  ) RETURNING id INTO audit_id;

  UPDATE audit_chain_state
  SET latest_hash = chain_entry_hash, updated_at = now()
  WHERE singleton = true;

  RETURN audit_id;
END;
$$;
