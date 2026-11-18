# Astra II-C D — event snapshot/restore owned index
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: D
START: 2026-11-18 23:35 MSK
BASE: event_queue blob 55552dc5bd99dd00fc998da5f77d306a7ef83c95
ASTRA: D deterministic event queue; eliminate redundant copying and scans without changing due ordering or ownership.
CODE SHA: a2f415751ea10314154785d9f57932fec1f73195
TEST SHA: 6ee4597a0da224c5fbf696fb4dd7ade13eb1cd33
FILES: godot/scripts/sim/event_queue.gd; godot/tests/p2_perf_d_event_snapshot_restore_oracle.gd
IMPLEMENTED: snapshot sorts shallow references using the original comparator before making one deep detached copy; restore builds positions and numeric due indexes in the same validation/owned-copy pass, staging all maps until successful atomic publication.
ORACLE: old deep-copy-first snapshot vs new snapshot; 400 events, cancellation, multiple ticks/phases, payload alias isolation, restore input alias isolation, duplicate sequence/invalid payload/invalid phase rejection, unchanged queue after failed restore, canonical dispatch order.
TEST: NOT_RUN (Godot/Windows deferred by user); CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED.
RISK: no measured speedup; snapshot comparator assumes ordering scalars are immutable during synchronous snapshot; full same-seed paid-tick/N38 parity pending.
NEXT ASTRA II-C: facility and market roster reuse between Head and station admin on due cycles, with ownership/install/remove/move oracle and bounded invalidation; avoid repeating previous N150 window patches.
