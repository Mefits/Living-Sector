-- Phase 18d: per-ship progression (levels, XP, banked retrofit points).
--
-- Stored as a JSON object `{level, xp, retrofit_points}` so future
-- fields (e.g. attribute scores, prestige) can land without another
-- migration. Existing rows default to the fresh level-1 shape.

ALTER TABLE ships
    ADD COLUMN progression TEXT NOT NULL DEFAULT '{"level":1,"xp":0,"retrofit_points":0}';
