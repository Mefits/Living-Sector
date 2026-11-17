# PERF C — N140/N84 active owned merge, 17.11.2026

Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262 only.

- CODE `65cedfc151d87c7d924cfa44a798c28d53187f27`: `godot/scripts/sim/phase2/unified_n140_ship_ai_dispatch.gd`. Previously `ships.duplicate(true)` copied all rows and `proposed[sid].duplicate(true)` copied every active row again, after `NativeAI.propose` had already detached the active fleet. Now deep-copy only sleeping source rows and transfer already-owned active proposal rows. The original source World is read-only, and N39 remains sole authoritative commit.
- TEST `7a95ed608cffb7fc536a6178f16cf329a0363d74`: `godot/tests/p2_perf_c_n140_n84_owned_active_merge_oracle_20261117.gd`. Actual N140AI.propose invocation with one active idle ship, one sleeping ship carrying paid contract/cargo/BT metadata; compares value to deep-copy oracle, checks nested mutable isolation and no invented paid commands.
- TEST: NOT RUN; CODE_UNVERIFIED. No Godot execution, no measured improvement. The 500-tick CI #43972442164 predates this change; do not attribute its PASS to this patch.
- Complexity: eliminates redundant recursive active-ship copy in N140/N84 merge; sleeping ships still detached exactly once. No cadence, fuel, cargo, contract, tie-break or N9 change intended.
- Next: run targeted test and N38 negative replay; obtain N140/N84 source-level copy site timings on same-seed ticks 100/600/900 and compare CPU ms/paid tick, p95, size of ships/BT/cargo. Check paid pickup/delivery and N9/BT/RNG exact parity before acceptance. Do not rerun 2600 CI per commit.
