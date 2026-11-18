# Astra II-C / D — numeric due buckets end-to-end
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: D
START: 2026-11-18 12:37 Europe/Moscow
BASE_SHA: ec22a65c054b3b3ca3f03e8cc55211dc9454b93f
ASTRA: D stations/markets/Head/events; deterministic event queue, avoid repeated due scans and allocations.
SCOPE: godot/scripts/sim/event_queue.gd; godot/tests/p2_perf_d_event_numeric_due_buckets.gd
PLAN: replace per-call string boundary materialization with nested integer tick/phase buckets in schedule/cancel/take_due/restore, preserve snapshot and event comparator, atomic failed restore, test positive and negatives.
CODE_SHA: 96988f0f9eecb231717dd85ddbf49909458cac1d
TEST_SHA: d009d2c99ef2421ca720a951f09547a77da94413
FILES: godot/scripts/sim/event_queue.gd; godot/tests/p2_perf_d_event_numeric_due_buckets.gd
DONE: Replaced string tick:phase boundaries with nested integer tick -> phase -> ID buckets on schedule, cancel, take_due and atomic restore. Kept swap-removal sole store, deterministic _less comparator, detached snapshot/restore payload and same sequence semantics.
ORACLE: 320 mixed events, cancellations, duplicate IDs, invalid schedule, failed restore atomicity, restored parity, nested payload alias, re-schedule and sequence monotonicity.
TEST: NOT_RUN (Godot unavailable; Actions deliberately not triggered)
PERFORMANCE: NOT_MEASURED
NEXT ASTRA II-C D: Head/faction repeated global contract scans and station roster across actual live callsites; preserve exact decisions and market pricing.
