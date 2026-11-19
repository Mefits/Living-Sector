# II-C N21 paid dock queue occupancy / stage
STATUS: IN_PROGRESS
OWNER: C
TIME: 2026-11-19 03:30 MSK
BASE_SHA: cce50befdae783bd4adfd78ca535e535a4a80aa4
ASTRA: II-C ship/contract/dock/route caches; dock occupancy, deterministic invalidation and paid-tick parity.
FILES: godot/scripts/sim/phase2/unified_n21_dock_queue_stage.gd; godot/tests/p2_perf_c_n21_occupancy_stage_oracle.gd
GOAL: remove repeated paid-tick dock queue and occupancy work without changing FIFO, receipts, fees, tie-break, World or N9 ownership. Positive and negative oracle including queue mutation, invalid actors, capacity and paid admission.
TEST: NOT_RUN
