ALTER FUNCTION goye_append_audit_event(uuid, text, text, uuid, uuid, jsonb)
  SECURITY INVOKER
  RESET search_path;
GRANT EXECUTE ON FUNCTION goye_append_audit_event(uuid, text, text, uuid, uuid, jsonb) TO PUBLIC;
