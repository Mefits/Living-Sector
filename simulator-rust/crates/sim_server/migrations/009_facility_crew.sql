-- Phase 19a: facility crew complement persistence.
--
-- Aggregate crew (count + morale + hunger + fractional food debt)
-- stored as a single JSON blob on each facility row. Default '{}'
-- hydrates to the per-facility-type crew default — existing facilities
-- that were already seeded get a fresh crew complement on first boot
-- after this migration.

ALTER TABLE facilities ADD COLUMN crew_state TEXT NOT NULL DEFAULT '{}';
