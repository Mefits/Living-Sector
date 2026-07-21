-- Phase 19-pre: persist the contract board across restarts.
--
-- The `contracts` table has existed since migration 001 but nothing
-- actually writes to it during normal runtime — the board lived only
-- in the in-memory AgentStore. On restart the board started empty,
-- which made fresh-boot worlds feel dead until a few ticks of
-- posting had run.
--
-- This migration adds the columns the Rust Contract struct grew after
-- 001 (Phases 18i / 18j / 18 CrewMission work): the "initial"
-- snapshot captured at post-time so age-based escalation / age-open
-- logic can run relative to the original values, plus the crew
-- mission template slug.
--
-- Defaults let old rows hydrate cleanly — initial_* fall back to the
-- live values on read, mission_category stays null except for
-- crew_mission kinds.

ALTER TABLE contracts ADD COLUMN initial_payment INTEGER NOT NULL DEFAULT 0;
ALTER TABLE contracts ADD COLUMN initial_min_reputation INTEGER NOT NULL DEFAULT 0;
ALTER TABLE contracts ADD COLUMN mission_category TEXT;
