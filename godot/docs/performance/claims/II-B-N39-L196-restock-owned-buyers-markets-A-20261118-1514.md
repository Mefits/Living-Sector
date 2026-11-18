# Astra II-B — N39 L196 N130 restock owned rows
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: A
START: 2026-11-18 15:14 Europe/Moscow
BASE HEAD: 321ebb97567f5034b3bef110ba4609de7291fabd
CLAIM COMMIT: 5bfec01ac7ec3d41b6620eedc5d7e82f8a5148f0
CODE SHA: d883fc7e803ade3d311a0275122f098fe3b23086
TEST SHA: bc65f76050e6c45639189f131fa77fd975bb05c4
ASTRA: II-B bounded owned write sets, local validators, versions & delta; N39 L196
FILES:
- godot/scripts/sim/phase1/n39_native_world_production.gd
- godot/tests/p2_perf_a_n39_l196_restock_owned_rows.gd

FIX: N156 repair candidates and lifecycle deltas detach their facility rows even on N130 cadence. Immediately before ServiceRestock.apply, a sorted conservative scan of the post-lifecycle state detaches all potentially writable same-faction live buyer/seller rows and their market rows; all other facility/market rows remain read-only. Multiple buyers of one seller share one detached seller row. Missing markets/sellers retain the original N130 rejection path. N9 fork, complete Schema.validate, Schema.accounts/N9 checks and atomic commit are unchanged.

TEST: NOT_RUN
CODE: CODE_UNVERIFIED
PERFORMANCE: NOT_MEASURED
TEST COVERAGE: two sequential paid buyers, shared seller, full deep World oracle, nested rollback/alias isolation, excluded abandoned/foreign rows and untouched markets. The test exercises the ownership algorithm, not a full N130 production paid tick.
RISK: N130 full production same-seed/N38 oracle and paid/rejected market scenarios still require execution. No GitHub Actions run per user request.
NEXT ASTRA II-B: audit remaining frequent L129 callers and bounded ownership for N39 source stages, coordinate ship/dock callers with C, add production-level full Schema/N9 and N38 parity fixture before claiming performance.
