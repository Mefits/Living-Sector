# PERF A handoff — 2026-11-17 — N154 paid shipyard modules

Branch: integration/perf-astra-5-workers-20261116, PR #262.
Code commit: 43bf01ffe8eecbc8107da8b6694359b7e685387c
Test commit: 190e8a024cf349906b617173093bea7130fa8802

Changed: godot/scripts/sim/phase1/n39_native_world_production.gd
Added: godot/tests/p2_perf_a_n154_module_owned_stage.gd

Replaced N154 _run_shipyard_modules() L4449 full World deep copy with shallow authoritative root and deep copies of facilities, populations and markets. Payroll.pay_shift mutates facility credits/work_shift and household wealth/employment; module manufacturing changes facility module_stock and market supply/history. All three domains detach before payroll; all other domains remain read-only. Existing Schema.validate, Schema.accounts, N9 ledger fork/receipt and atomic publication are untouched. Source blocked stage cannot mutate canonical World.

Test models both the full deep-copy oracle and bounded stage, with negative nested alias regression. This test does not invoke production _run_shipyard_modules or actual payroll.

Status: CODE_COMMITTED; CODE_UNVERIFIED; TEST_ADDED_NOT_RUN. No runtime or CI execution; no measured speedup and no late-tick parity claim. Existing #43972442164 PASS predates this patch.

Next: targeted real funded shipyard payroll test (including blocked wages), N38 restart and same-seed early/late phase timings. Prioritize measured deep:L129 read caller frequency; do not repeat 99ab25e9 or 1676db61. No merge, no force push.
