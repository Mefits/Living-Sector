# Astra II-C D — N135 commodity supplier index
STATUS: IN_PROGRESS
OWNER: D
TIME: 2026-11-19 11:41 Europe/Moscow
BASE_SHA: fac5c7faa3af17c65cdb77f77d37703cc62e5638
ASTRA: II-C station/faction/market rosters; avoid repeated full supplier scans.
INTENDED_FILES: godot/scripts/sim/phase2/unified_station_demand_phase.gd; godot/tests/p2_perf_d_n135_commodity_index.gd
PLAN: per-proposal commodity-keyed sorted eligible suppliers, preserve all stock validation, reservations, prices, stable source order, no persistent cache. Positive and negative reference/oracle tests.
RISK: nonnumeric stock, negative/nonfinite stock, fractional affordability and source tie-break.
TEST: NOT_RUN
