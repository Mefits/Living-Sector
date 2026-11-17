# C handoff — N14/N140 owned fleet, 2026-11-16 23:24 MSK

CODE COMMIT: 2f645f5beaec4fc6a328f0f6ce21f864e52b43c4
TEST COMMITS: ffcb3ea320bd499dde46dc0b5e3b35081a37b133, ee9f9f2c0adb8f54f8ed2aa8b1a957358aa7935b
BRANCH: integration/perf-astra-5-workers-20261116, draft PR #262 only

## Change
- `godot/scripts/sim/phase2/unified_ship_phase.gd`: in actual `advance` N14 hotpath reuse the deep-detached `gate["ships"]` produced by N140.stage rather than deep-copying the entire fleet again. N140.stage explicitly calls `world["ships"].duplicate(true)`; N14 is the exclusive consumer and still deep-copies the final changed output per ship before publication.
- `godot/tests/p2_perf_c_n140_owned_fleet_detach_oracle_20261116.gd`: source World/nested cargo/LOD alias negatives, old-copy parity, final publication isolation, no fake transit/fuel/cargo change. Uses real ShipState fixture and N140 gate.

## Evidence and limitations
- Confirmed source-level one fewer O(fleet serialized size) deep copy per actual N14 advance invocation. No new cache or invalidation.
- TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No Godot runtime or same-seed benchmark executed here. Measured benefit: UNKNOWN; baseline ships ~117.65s / 300 late ticks is aggregate, not attributable to this copy.
- No changes to N9, N39, N38, N158, contracts, fuel/cargo rules, source cadence, BT/RNG, AI budget, or dock queue.
- Safety prerequisite: N140.stage returns detached rows and N14 alone owns them; verify in Godot test and exact replay before accepting.

## Next concrete step
Run targeted N140 ownership oracle, then same-seed before/after paid ticks 100/600/900 with N14/N140 call counts, CPU avg/p95, ship+dock phase totals and fleet size; check N38 restart, N9/BT/RNG/contract/cargo parity. If no material win, revert. Profile repeated ShipState.restore and N140.stage copies next; coordinate any N39 deep snapshot issue with A, do not edit N39.
