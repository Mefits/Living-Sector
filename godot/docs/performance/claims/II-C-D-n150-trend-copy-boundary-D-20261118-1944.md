# Astra II-C D — N150 trend-copy boundary
STATUS: IN_PROGRESS
OWNER: D
START: 2026-11-18 19:44 MSK
BASE_SHA: 516b11f7291f5eb9c467fa51ebd94b67389377f7
ASTRA: II-C station/faction/market rosters; eliminate redundant market DTO/materializations on actual tick path.
INTENDED_FILES: godot/scripts/sim/phase1/n150_native_full_market_tick.gd; godot/tests/p2_perf_d_n150_trend_copy_boundary_20261118.gd
EXPECTED: exact legacy-vs-optimized market result, large restored trend histories, no mutable aliases, malformed input failure and tick cadence. Godot/Actions not run.
