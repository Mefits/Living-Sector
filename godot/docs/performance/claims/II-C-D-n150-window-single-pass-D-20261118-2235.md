# Astra II-C — N150 retained consumption window single-pass
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: D
TIME: 2026-11-18 22:35 MSK
BASE: shared PR #262, n150 blob 70da4d2dc6bd92b4f22639319997040fadc7decd
ASTRA: II-C station/faction/market rosters; D markets repeated scans
FILES: godot/scripts/sim/phase1/n150_native_full_market_tick.gd; godot/tests/p2_perf_d_n150_window_single_pass.gd
SCOPE: eliminate second per-commodity traversal of retained consumption rows during each paid market tick, preserving validation, floating-point summation order, independent ownership, prices and errors.
TEST: oracle old retained-window summation vs fused aggregation, expiry boundary, negative malformed sample, independent World.

CODE SHA: cdbe1554b41986c8c7c60fc18cdd135d6d26e40e
TEST SHA: 424552390e973051bd1279092d6780d84a27a44d, 9977db6dd3c3d59913b47f1fd24c29c80a69257e
TEST: NOT_RUN (no Godot runtime; GitHub Actions prohibited)
PERFORMANCE: NOT_MEASURED
RESULT: _owned_flow_without_expired now deep-owns retained rows and sums their quantities in the same original order. tick_one_market reuses scalar observed totals, removing the second validation/compaction/summation pass through retained rows. No World references are returned. Price/shortage/expiry/seed warmup logic unchanged.
ORACLE: counts 0/1/50/500/1200; tick 1/100/101/400; retained row order, demand exact, price unchanged, source immutability, nested alias mutation, malformed expired sample and malformed window.
RISK: test execution and same-seed paid-tick performance/parity pending.
NEXT ASTRA II-C: remove repeated facility/market roster construction across Head and station administrators only after checking callsite lifetime and ownership/invalidation on install/remove/transfer.
