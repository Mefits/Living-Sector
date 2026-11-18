# Astra II-B — N39 L196/N18 to LOD row ownership
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: A
START: 2026-11-18 12:11 Europe/Moscow
BASE HEAD: 3bc3f1cdc795ab0a172b94066f355bd075dc33e5
ASTRA: II-B bounded owned write sets / rollback / alias isolation. Fix mutable facility row alias at N18 staffing → LOD advance, avoid broad copies for LOD-only changes.
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n39_lod_owned_rows.gd
EXPECTED: old vs optimized LOD state, no-op and due ticks, negative alias regression, full Schema oracle; runtime NOT_RUN without Godot.

CODE SHA: 04f735e6ef98d4dbfd6c3ac27d935882f1d81ce6
TEST SHA: eddb07a7c9a9fb91d75823668364fa5eabc8f7db; correction 55d62dcbe499ce1ad5592a268b2cea534988fde6
FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n39_lod_owned_rows.gd
DONE: N39 run_tick LOD read pass computes deterministic due cursors, then detaches only changed facility rows and shallow World/root; preserves sorted ids, cadence and next tick, prevents in-place mutation across N18 owned stage. Full Schema.validate on cursor publish; no N9 money mutation.
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED. Positive early/due/sleep cadence and full deep-copy oracle, nested alias negative. Test is isolated algorithm oracle, not full production runtime.
RISK: Added full Schema check on cursor publish; performance impact unknown and may outweigh copy savings. Requires measured early/late phase profile before acceptance. No Actions launched.
NEXT ASTRA II-B: N39 lifecycle L196 facilities deep clone each tick: bound real repair/restock/LOD row ownership across Payroll/ServiceRestock with full Schema+N9 oracle; coordinate if writer crosses domain.
