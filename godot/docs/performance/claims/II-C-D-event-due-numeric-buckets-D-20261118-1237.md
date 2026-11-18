# Astra II-C / D — numeric due buckets end-to-end
STATUS: IN_PROGRESS
OWNER: D
START: 2026-11-18 12:37 Europe/Moscow
BASE_SHA: ec22a65c054b3b3ca3f03e8cc55211dc9454b93f
ASTRA: D stations/markets/Head/events; deterministic event queue, avoid repeated due scans and allocations.
SCOPE: godot/scripts/sim/event_queue.gd; godot/tests/p2_perf_d_event_numeric_due_buckets.gd
PLAN: replace per-call string boundary materialization with nested integer tick/phase buckets in schedule/cancel/take_due/restore, preserve snapshot and event comparator, atomic failed restore, test positive and negatives.
TEST: NOT_RUN
