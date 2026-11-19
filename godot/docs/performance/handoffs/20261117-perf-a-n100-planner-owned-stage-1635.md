# PERF A — N100 planner-only World publish (17.11.2026)

Branch: `integration/perf-astra-5-workers-20261116`, PR #262.

Code commit: `a8a3fa9d92fc1b07c872fabf7fac0e76ad294c47`.
Test commit: `edfae289860b3a12dd3316aba612d4eb111fa049`.

Changed `godot/scripts/sim/phase1/n39_native_world_production.gd`: N100 `apply_native_hybrid_planning` at profiling site L4822 previously deep-copied the entire World. It now shallow-copies the root and deep-copies only `native_planner_records`, the sole nested domain this path writes, before assigning `native_planner_last_tick`. Full Schema.validate and accounts comparisons remain unchanged. No ledger, receipts, RNG, BT or source cadence changed. No mutable planner alias escapes into authoritative World. N100 planning only runs on due ticks and is not yet demonstrated to dominate late tick CPU.

Added `godot/tests/p2_perf_a_n100_planner_owned_stage.gd` with full deep-copy oracle, rejection isolation, and nested mutable-alias negative fixture. Test is an ownership model test, not an invocation of production N100.

Verification: CODE_COMMITTED; CODE_UNVERIFIED; TEST_ADDED_NOT_RUN. No CI or performance proof. Historical PASS #43972442164 predates these commits. No claim of improvement to Windows tick2329. Next: execute targeted test plus paid N100 planning and N38 restart; then measure copy site calls/time before and after at early and late same-seed windows. Prioritize measured L129 callers and L196 over rare planner paths. Do not duplicate 99ab25e9 or 1676db61.
