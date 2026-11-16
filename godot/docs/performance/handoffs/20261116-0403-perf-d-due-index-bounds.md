# PERF D handoff — 2026-11-16 04:03 MSK

Branch: `integration/perf-astra-5-workers-20261116`; draft PR #262.
Code commits: `6f7857fa2ac074d71bcf0ee3193b46deb938581b`, `381f65519f7f2db5aeec5d295fb4dd5f5568c3fa`.
Test commits: `eb31594623d961cf28ccb3b8e77ca5cfae19430e`, `f29b6de62dce7350460bb1ca4b2a5eb99f904671`.

## Changes
- `godot/scripts/sim/phase2/p2_perf_d_due_index.gd`: bounded event count and exact MAX_TICK / sequence limits matching authoritative EventQueue, atomic rebuild rejecting duplicate pending sequences, incremental sequence membership updated by add/remove/take_due. This closes silent divergence on invalid event snapshots and sequence collisions.
- `godot/tests/p2_perf_d_due_index_bounds_check.gd`: negative max tick/sequence, duplicate sequence, rollback after invalid rebuild, cancelled ID and actual EventQueue ordering oracle.

## Evidence
CODE_UNVERIFIED; TEST_ADDED_NOT_RUN. No Godot execution, timing measurements, N38 restart or FPS evidence. Static review of referenced EventQueue and experimental index paths/signatures. Live `event_queue.gd` remains untouched; opt-in index is NOT wired into runtime. No Actions triggered.

## Next
Execute `p2_perf_d_due_index_check.gd`, `p2_perf_d_cancel_index_check.gd`, and `p2_perf_d_due_index_bounds_check.gd` under Godot 4.7.2. Then add bounded equal-seed take_due/cancel benchmark and N38 restore/restart oracle before any backend switch. No lease held; domain D isolated.
