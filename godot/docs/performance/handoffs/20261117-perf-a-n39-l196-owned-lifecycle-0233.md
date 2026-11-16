# PERF A handoff — 2026-11-17 02:33 MSK — N39 L196 lifecycle stage

Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262.

Code: `2d4b6e07692176834d2d0f25c00fa9226fc3425b`.
Test: `2803d0d6f90b88c2ea0e460fd55bbd40ba605cbd`.

Changed `godot/scripts/sim/phase1/n39_native_world_production.gd` in `run_tick`: replaced per-paid-tick `_copy_world("L196", true)` with shallow root plus deep copies of the three owned domains `facilities`, `markets`, `populations`. Verified source writers: `Payroll.pay_shift` mutates facility credits/work_shift and population wealth/employment; `ServiceRestock.apply` mutates facility reserves/credits and market supply. Lifecycle proposal writes are applied to facilities. Existing full `Schema.validate`, `Schema.accounts`, N9 fork/receipts, and atomic publication remain unchanged. The root shares only non-owned domains, which this stage must not mutate. Subsequent recipes/mining use the committed, detached domains.

New test: `godot/tests/p2_perf_a_n39_l196_owned_lifecycle.gd` compares owned stage with full deep-copy oracle and tests rejected-stage isolation plus a negative shallow-alias fixture.

Status: CODE_COMMITTED; CODE_UNVERIFIED; TEST_ADDED_NOT_RUN. No Godot runtime execution, CI, early/late same-seed benchmark, N38 restart or performance proof in this shift. Expected reduction is elimination of copying unrelated growing ships/contracts/history at this site; actual ms/tick and full economic parity remain unmeasured. Baseline site was L196 every paid run_tick, not instrumentation L129.

Do not duplicate 99ab25e9 or 1676db61. Latest independent CI #43972442164 PASS covers earlier HEAD only; this patch is not included.

Next: run targeted test, exact N39/N9/N38/BT/RNG/contract/cargo same-seed early/late parity and 900-tick bounded profile; inspect source writers for any unlisted domain mutation before accepting. Coordinate with E for one consolidated checkpoint, no per-commit CI.
