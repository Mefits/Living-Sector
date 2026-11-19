# Astra II-C D — N150 sparse consumption-window copy
STATUS: IN_PROGRESS
OWNER: D
DATE: 2026-11-19 15:36 MSK
BASE SHA: 54dddfafa5a1b5953d317beb935a2e9dc84b79e3
ASTRA: II-C station/faction/market rosters; eliminate redundant full scans/materializations in real market paid path.
INTENDED: godot/scripts/sim/phase1/n150_native_full_market_tick.gd; godot/tests/p2_perf_d_n150_sparse_window.gd
GOAL: avoid repeated deep-copy work for large market consumption histories while preserving exact floating-point accumulation order, malformed-row rejection, no World alias, and same price/shortage/ordering.
TEST: positive and negative source oracle, stale cutoff, malformed expired samples, detached output.
