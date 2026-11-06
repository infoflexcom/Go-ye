-- Roll back Unassigned Pool and initial follow-up plan.
REVOKE EXECUTE ON FUNCTION goye_assign_convert_to_parish(uuid, uuid, uuid) FROM goye_runtime;
DROP FUNCTION IF EXISTS goye_assign_convert_to_parish(uuid, uuid, uuid);
DROP TABLE IF EXISTS follow_up_tasks;
REVOKE UPDATE (full_name_encrypted, phone_encrypted, address_encrypted) ON TABLE converts FROM goye_runtime;
GRANT UPDATE ON TABLE converts TO goye_runtime;
ALTER TABLE converts DROP COLUMN IF EXISTS assigned_by;
ALTER TABLE converts DROP COLUMN IF EXISTS assigned_at;
DROP TYPE IF EXISTS follow_up_task_status;
DROP TYPE IF EXISTS follow_up_task_type;
