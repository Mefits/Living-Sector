# PERF C handoff — route FIFO scalar columns (2026-11-16, run 11)

- Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262.
- CODE COMMIT: `111dc41077c77d75f0f12b1126d2620015e36af0`.
- TEST COMMIT: `518dd95639dc0e1029fbd43ec36d2fb45f5f3da8`.
- Files: `godot/scripts/sim/route_graph.gd`, `godot/tests/p2_perf_c_route_fifo_columns_oracle.gd`.
- Change: replace one dynamically allocated two-element Array per shortest-path cache miss with two typed Array[String] FIFO columns. Eviction and compaction consume matching columns at the same head. Graph reload clears both; failed reload leaves both untouched. No World/ledger/ship/contract/fuel/AI behavior changed.
- Test: 12,290 distinct negative routes, multiple FIFO compactions, newest hit/oldest eviction, cached/naive positive route, mutable isolation, failed load rollback, successful load reset.
- TEST EXECUTED: NOT RUN; CODE_UNVERIFIED / TEST_ADDED_NOT_RUN (no Godot execution). Static source review only. No measured speedup or memory benchmark. Existing `p2_perf_c_route_fifo_oracle.gd` remains applicable.
- Next: execute both FIFO oracles and measure allocations/route cache cost in an agreed bounded checkpoint; then compare N153 paid-contract decisions, fuel/cargo and N38 restart before accepting further ship-phase changes.
