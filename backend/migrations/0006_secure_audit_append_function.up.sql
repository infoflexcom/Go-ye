-- The append function alone can advance the chain state; callers still require a valid transaction secret.
ALTER FUNCTION goye_append_audit_event(uuid, text, text, uuid, uuid, jsonb)
  SECURITY DEFINER
  SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION goye_append_audit_event(uuid, text, text, uuid, uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION goye_append_audit_event(uuid, text, text, uuid, uuid, jsonb) TO goye_runtime;
