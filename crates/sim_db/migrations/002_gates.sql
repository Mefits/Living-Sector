-- Phase 17: Inter-system jump gates.
--
-- Gates are ordinary `facilities` rows with `facility_type = 'gate'` plus
-- a `gate_paired_id` naming their counterpart on the far side. Fee and
-- throughput knobs live as constants in `sim_core::agents::facility`
-- today so we don't need extra columns — add them here later if per-gate
-- tuning becomes useful.

ALTER TABLE facilities
    ADD COLUMN gate_paired_id TEXT;

CREATE INDEX IF NOT EXISTS idx_facilities_gate_pair ON facilities(gate_paired_id);
