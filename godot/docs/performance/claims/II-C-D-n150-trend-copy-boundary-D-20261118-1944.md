# Astra II-C D — N150 bounded trend-copy on sampling boundary
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: D
START: 2026-11-18 19:44 MSK
BASE_SHA: 516b11f7291f5eb9c467fa51ebd94b67389377f7
ASTRA: II-C market DTO/materializations, retained trend history on paid tick.
CODE_SHA: 36a290c5400b96a97460f4d90f74da6b11c38abf
TEST_SHA: 9535483783a98ff8ebb49b8fe2826ba03de79b68
FILES:
- godot/scripts/sim/phase1/n150_native_full_market_tick.gd
- godot/tests/p2_perf_d_n150_trend_copy_boundary_20261118.gd
CHANGES: tick_one_market uses _owned_market_for_tick. At a 16-tick sample boundary with >=200 historical trend samples, deep-copy only the final 199 existing trend rows; the source then appends one and retains exactly 200. Other fields, including unknown extension dictionaries, remain deep-owned. Non-sampling ticks and histories shorter than 200 keep original deep-copy behavior. The source market is never mutated.
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED. Test covers 0/1/199/200/201/1200 rows, exact result comparison against pretrimmed full-copy oracle, non-sample retention, nested alias isolation, invalid shortage counter.
RISK: Godot parser/runtime and full same-seed N38 parity pending; this optimization primarily helps oversized restored histories at sample boundaries, not the steady 200-row market.
NEXT ASTRA II-C: find and eliminate repeated live market/faction scans in N150/Head station roster, with lifecycle invalidation and exact decision/price oracle; measure early/late paid ticks when allowed.
