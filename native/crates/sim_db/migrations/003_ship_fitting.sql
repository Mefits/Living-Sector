-- Phase 18b: per-ship subsystem fitting persistence.
--
-- `fitting` is a JSON object keyed by slot name
-- (`engine` / `cargo_bay` / `sensors` / `reactor` / `comms`) mapping to a
-- module slug from `sim_core::modules::CATALOG`, or JSON null for an
-- empty slot. Existing rows default to `'{}'` so the loader falls back
-- to the tier-1 default per slot — gameplay-identical to a pre-18b
-- ship.

ALTER TABLE ships
    ADD COLUMN fitting TEXT NOT NULL DEFAULT '{}';
