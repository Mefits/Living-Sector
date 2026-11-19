# PERF C — ShipState restore single detach (2026-11-17)

CODE SHA: d5e4d77547e74d792cba43640ef2006d49f7a5a6
TEST SHA: 29e482105661c65c10b64d5e5fea22ac464f8ac8

Changed `godot/scripts/sim/phase2/unified_ship_phase.gd`: the actual N14/N84 `_load` path no longer deep-copies every World ship into the temporary records array before calling `ShipState.restore`. `ShipState.restore` validates the full fleet and deep-copies each record itself. This eliminates one full-fleet deep copy per `_load` invocation, while preserving validation, deterministic sorted IDs, token cursor and downstream publication copies. No N39/N9/N158 changes.

Added `godot/tests/p2_perf_c_ship_restore_single_detach_oracle_20261117.gd`: negative nested cargo/crew alias, invalid cargo, stale transit token. Source reviewed against `ship_state.gd::restore`, which performs `record.duplicate(true)` after validation. Test fixture uses catalog class miner; validate class against live catalog at runtime.

TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No speedup measured; baseline ships 117.65 s / 300 ticks and dock 26.49 s / 300 ticks are whole-phase numbers, not attribution to this copy.

NEXT: bounded same-seed early/late CPU per paid tick and N14/N84 site timings, test fixture/parser, N38 restart and exact BT/RNG/contract/cargo parity before acceptance. Do not run long CI per commit.
