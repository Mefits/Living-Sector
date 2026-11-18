# Astra II-C D — event snapshot/restore owned index
STATUS: IN_PROGRESS
OWNER: D
START: 2026-11-18 23:35 MSK
BASE: PR #262 canonical integration/perf-astra-5-workers-20261116 (event_queue blob 55552dc5bd99dd00fc998da5f77d306a7ef83c95)
ASTRA: D events — deterministic event queue, avoid repeated scans/copies while preserving (due_tick,phase,entity_id,sequence), atomic restore and payload ownership.
INTENDED: godot/scripts/sim/event_queue.gd; godot/tests/p2_perf_d_event_snapshot_restore_oracle.gd
CHECK: snapshot canonical ordering vs legacy deep-copy-first; restore valid/invalid atomicity, cancel/schedule/take_due and alias isolation; TEST_NOT_RUN until Godot available.
