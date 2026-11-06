-- Corrects the initial E.164 regular expression before deployment.
-- Rollback: restores the original 0001 constraint for strict migration reversibility.
ALTER TABLE users DROP CONSTRAINT users_phone_format;
ALTER TABLE users ADD CONSTRAINT users_phone_format
  CHECK (phone_normalized IS NULL OR phone_normalized ~ '^\+[1-9][0-9]{6,14}$');
