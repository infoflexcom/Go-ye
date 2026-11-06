-- Roll back daily hierarchy roll-up summaries.
DROP TRIGGER IF EXISTS converts_maintain_rollup_after_write ON converts;
DROP FUNCTION IF EXISTS goye_maintain_convert_rollup();
DROP FUNCTION IF EXISTS goye_apply_convert_rollup(uuid, date, convert_stage, bigint);
DROP TABLE IF EXISTS convert_rollup_daily;
