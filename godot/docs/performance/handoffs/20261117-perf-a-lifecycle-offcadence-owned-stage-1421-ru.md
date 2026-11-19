# PERF A — N39 lifecycle off-cadence bounded writes — 2026-11-17

Branch: integration/perf-astra-5-workers-20261116, PR #262.
Code: 3785a60e3878686da4246dbbc79837601d5851e2
Test: ded5fa20e2e4e46ddf95a23e5ec2410cb6fd1c39; fixture correction cb51c3cdcc5bbb55b13b08624787404899dfbc31.

Changed: godot/scripts/sim/phase1/n39_native_world_production.gd and godot/tests/p2_perf_a_n39_lifecycle_off_cadence_owned_stage.gd.

In run_tick N156/N130, facilities remain detached every tick. Market deep copy now occurs only when initial.due.restock, population deep copy only when repair_candidates nonempty. On no-repair/no-restock ticks these domains are read-only: N130.apply returns before writes on non-cadence ticks; payroll repair loop has zero iterations. Full Schema.validate/accounts oracle, ledger fork conditions and atomic commit are unchanged. Existing L196_owned_root is already shallow and was not reverted. N9/N158 fixes untouched.

Expected structural effect: removes two deep domain copies on ordinary no-repair/non-restock ticks. Exact CPU improvement, p95, paid-tick distribution, and late-tick growth are NOT MEASURED. CODE_COMMITTED / CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No CI triggered.

Regression compares detached facilities with full deep World oracle, invokes real N130 off-cadence no-op, checks negative nested alias and paid-stage isolation. It does not execute a full production run_tick or N156 paid repair; requires targeted Godot execution and same-seed N9/N39/N38/BT/RNG parity before acceptance.

Next: run targeted regression and same-seed 160/500 real paid ticks, then instrument per-site time and copy counts on early/late windows. Coordinate with E for one bounded CI checkpoint, not a CI run per commit. Verify paid repair and due restock cases, N38 restart; investigate remaining N39 publish copies only if measured.
