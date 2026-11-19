# Astra II-C D — Head market location lookup
STATUS: IN_PROGRESS
OWNER: D
TIME: 2026-11-19 10:40 MSK
BASE FILE SHA: 11933eccac3cab1041906f18aa6d17e0811e8474
ASTRA: station/faction/market rosters; avoid repeated full scans; exact Head decisions and market ordering.
INTENDED: godot/scripts/sim/phase2/unified_native_hybrid_planning.gd; godot/tests/p2_perf_d_head_market_location_lookup.gd
PLAN: derive candidate market locations from owned facility locations rather than scan every market per faction; preserve lexicographic market order, ownership/mismatch failure, detached DTO; independent naive oracle and negative mutation cases.
TEST: NOT_RUN
