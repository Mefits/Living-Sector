# Astra II-C / D — Head capture no-goal hotpath
STATUS: IN_PROGRESS
OWNER: D
START: 2026-11-18 13:40 MSK
BASE SHA: c1981cebc86a5fef6fb775a8b05ceceb1f4ec628
ASTRA: station/faction/market rosters, repeated full scans in Head planning
FILES: godot/scripts/sim/phase2/unified_native_hybrid_planning.gd; godot/tests/p2_perf_d_head_no_goal_capture.gd
EXPECTED: avoid full World facility/market/ship/contract scans on head with no source stock goal; preserve original preflight errors, source decisions and RNG; positive/negative oracle
TEST: NOT_RUN
