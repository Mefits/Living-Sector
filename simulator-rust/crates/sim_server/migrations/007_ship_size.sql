-- Phase 18f: ship size (scale tier).
--
-- Size is orthogonal to `class`: a size-3 tanker and a size-5 tanker
-- differ in scale while sharing a role. Stored as the snake_case
-- enum name (tiny / small / medium / large / huge / massive); empty
-- string falls back to the class's `default_size` at load time.

ALTER TABLE ships
    ADD COLUMN size TEXT NOT NULL DEFAULT '';
