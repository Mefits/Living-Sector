# II-C N21 paid dock queue occupancy / stage
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: C
TIME: 2026-11-19 03:30 MSK
BASE_SHA: cce50befdae783bd4adfd78ca535e535a4a80aa4
ASTRA: II-C ship/contract/dock/route caches; dock occupancy, deterministic invalidation and paid-tick parity.
FILES: godot/scripts/sim/phase2/unified_n21_dock_queue_stage.gd; godot/tests/p2_perf_c_n21_occupancy_stage_oracle.gd
GOAL: remove repeated paid-tick dock queue and occupancy work without changing FIFO, receipts, fees, tie-break, World or N9 ownership. Positive and negative oracle including queue mutation, invalid actors, capacity and paid admission.
TEST: NOT_RUN

CODE_SHA: 130677aa67d0fa4ca2842d8c680c2e1aca2059e5
TEST_SHA: 9ddbceec14a60dd15c8a9ec36270db6e44cccf49
TEST: NOT_RUN
CODE_UNVERIFIED: true
PERFORMANCE_NOT_MEASURED: true
CHANGED: N21 advance now builds one invocation-local ordered list of only facilities with nonempty queues; counts physical dock occupancy only for these queue owners, with explicit zero entries to prevent fallback full ship scans in _fee/_admit. Source queue order, capacity, fee, N9 and receipt operations unchanged. Rebuilt per paid tick/N38 restore, no persistent index.
NEGATIVES: 2000 facilities/500 ships sparse roster, queue add/remove, dock occupancy change, empty queue, existing paid FIFO oracle (insolvent, stale, duplicate retry, N9 conservation).
RISK: No Godot runtime available; exact paid tick parity and speed unmeasured.
NEXT_ASTRA: II-C N84/N153 dock/contract candidate occupancy and paid-tick 24/100/500 BT/cargo/fuel/route oracle; avoid already optimized N140 no-AgentLod.
