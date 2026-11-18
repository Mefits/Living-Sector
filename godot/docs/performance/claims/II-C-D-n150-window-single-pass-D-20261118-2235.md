# Astra II-C — N150 retained consumption window single-pass
STATUS: IN_PROGRESS
OWNER: D
TIME: 2026-11-18 22:35 MSK
BASE: shared PR #262, n150 blob 70da4d2dc6bd92b4f22639319997040fadc7decd
ASTRA: II-C station/faction/market rosters; D markets repeated scans
FILES: godot/scripts/sim/phase1/n150_native_full_market_tick.gd; godot/tests/p2_perf_d_n150_window_single_pass.gd
SCOPE: eliminate second per-commodity traversal of retained consumption rows during each paid market tick, preserving validation, floating-point summation order, independent ownership, prices and errors.
TEST: oracle old retained-window summation vs fused aggregation, expiry boundary, negative malformed sample, independent World.
