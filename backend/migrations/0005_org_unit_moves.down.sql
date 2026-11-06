DROP FUNCTION IF EXISTS goye_move_org_unit(uuid, uuid);
-- The 0001 trigger function has no move allowance; reapply it by restoring its original definition
-- from the 0001 migration during a full down migration sequence.
