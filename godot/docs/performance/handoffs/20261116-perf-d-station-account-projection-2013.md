# PERF D handoff — 2026-11-16 20:13 MSK — N18 station account projection

CODE COMMIT: c4cd697f68e8b5d636ba568da80a26fed3983d4d
TEST COMMIT: cbb7e880b838f8e614035c204a7c23e90c8ba490
FILES: godot/scripts/sim/phase2/unified_native_station_administration_phase.gd; godot/tests/p2_perf_d_station_account_projection_20261116.gd

Change: Actual N18 due-cycle station roster computes Schema.facility_account(owner_id) once per market instead of once per facility job plus market_owner. Scoped per market, not persisted; owner changes re-evaluated. World, N9, N158, prices, RNG, staffing priorities, cadence and AI search budget unchanged.

TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. Oracle checks per-job versus per-market account across 0/1/64/128 jobs and owner transfers. Full N18/N38 restart parity not verified.

Expected reduction in repeated account conversion calls, CPU benefit UNMEASURED. Baseline factions 39.34s / markets 39.43s across ticks 601–900 cannot be attributed to this site. No claim of late-tick fix.

NEXT: identify dominant N18/Head or N150 DTO scan using existing same-seed site profile, then implement measured hotpath change and bounded early/late CPU checkpoint with exact N9/N39/N38/BT/RNG/contracts/cargo parity. No per-commit long CI.
