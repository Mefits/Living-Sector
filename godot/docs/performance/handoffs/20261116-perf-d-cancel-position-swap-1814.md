# PERF D — cancel position map, 16.11.2026

- Code commit: `1cda11f27bb6609d492f7ec24968beda9114749b`
- Test commit: `40c9aeed5465addd1068c58e23ea6edc6d5993fc`
- Files: `godot/scripts/sim/event_queue.gd`, `godot/tests/p2_perf_d_cancel_position_oracle_20261116.gd`
- Baseline evidence: markets and factions each ~39s/300 ticks at tick900; no per-site event cancellation count supplied. This patch does NOT claim to explain those phase totals.
- Implementation: map event ID to index in the authoritative pending array. Cancel uses swap-with-last and pop instead of linear search/remove_at. Schedule, restore and take_due maintain/rebuild map. Snapshot and dispatch retain deterministic sort by due_tick, phase, entity_id, sequence. Failed restore preserves current queue and map.
- Complexity: cancel O(1) expected vs O(E) previously; take_due with matching events remains O(E), and rebuilds the map O(E). Empty boundaries still use due counts. No second authoritative event store.
- Test: cancel first/middle/last, moved index, duplicate cancel, unknown kind, invalid restore atomicity, replay across phases, exact order and repeat due.
- Status: CODE_UNVERIFIED; TEST_ADDED_NOT_RUN (no Godot execution). Measured speedup: NOT MEASURED. No CI launched.
- Next code step: use phase/site counters to establish whether event cancellations or due scans contribute materially to late-tick growth. If take_due dominates, optimize the actual live path with a verified indexed removal scheme and oracle. Before acceptance run same-seed early/late CPU per paid tick, p95, N38 restart and exact N9/N39/BT/RNG/contract/cargo parity.
