-- Roll back Phase 2 convert capture foundation.
DROP TABLE IF EXISTS converts;
DROP FUNCTION IF EXISTS goye_prepare_convert_update();
DROP TYPE IF EXISTS consent_capture_method;
