-- Phase 18e: facility subsystem fitting.
--
-- Mirror of ships.fitting but with 2 slots (production, automation)
-- instead of 5. Stored as `{slot: slug | null}` JSON. Existing rows
-- default to `'{}'` which the loader hydrates into a tier-1-default
-- (neutral) fitting.

ALTER TABLE facilities
    ADD COLUMN fitting TEXT NOT NULL DEFAULT '{}';
