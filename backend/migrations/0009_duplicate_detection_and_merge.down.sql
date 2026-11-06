-- Roll back duplicate detection and controlled merge.
REVOKE EXECUTE ON FUNCTION goye_merge_converts(uuid, uuid, uuid) FROM goye_runtime;
DROP FUNCTION IF EXISTS goye_merge_converts(uuid, uuid, uuid);
DROP INDEX IF EXISTS follow_up_tasks_pending_convert_type_unique;
ALTER TABLE follow_up_tasks ADD CONSTRAINT follow_up_tasks_convert_type_unique UNIQUE (convert_id, task_type);
DROP POLICY IF EXISTS follow_up_tasks_update_scope ON follow_up_tasks;
REVOKE UPDATE (phone_lookup_hash) ON TABLE converts FROM goye_runtime;
ALTER TABLE converts
  DROP CONSTRAINT IF EXISTS converts_cannot_merge_into_self,
  DROP CONSTRAINT IF EXISTS converts_merge_consistent,
  DROP COLUMN IF EXISTS merged_by,
  DROP COLUMN IF EXISTS merged_at,
  DROP COLUMN IF EXISTS merged_into_id,
  DROP COLUMN IF EXISTS phone_lookup_hash;
