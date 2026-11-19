# Astra II-C D — N135 commodity supplier index
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: D
TIME: 2026-11-19 11:41 Europe/Moscow
BASE_SHA: fac5c7faa3af17c65cdb77f77d37703cc62e5638
ASTRA: II-C station/faction/market rosters; avoid repeated full supplier scans.
INTENDED_FILES: godot/scripts/sim/phase2/unified_station_demand_phase.gd; godot/tests/p2_perf_d_n135_commodity_index.gd
PLAN: per-proposal commodity-keyed sorted eligible suppliers, preserve all stock validation, reservations, prices, stable source order, no persistent cache. Positive and negative reference/oracle tests.
RISK: nonnumeric stock, negative/nonfinite stock, fractional affordability and source tie-break.
TEST: NOT_RUN

CODE_SHA: a790fee1496755c578330ef23f433b0c8b65eecf
TEST_SHA: 70a0c0f08ce36d1d283444c202f135d211814ec9 (initial 020e78e922b6f51bb725eeb6e89a2195fe96b576)
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED
CHANGED: N135 propose() indexes candidate suppliers by actual numeric nonzero commodity supply in canonical sorted source order. Full market preflight, source validation, allocation, reservation, fractional prices and invalid negative/nonfinite stock retained. Index is rebuilt per call; no World alias retained across calls.
REGRESSION: 80 irrelevant markets, 3 competing suppliers, order oracle via naive full scan, physical reservation, moved owner, changed stock, negative/nonfinite stock and missing owner.
RISK: No Godot runtime execution or paid-tick before/after benchmark yet.
NEXT: Astra II-C Head/faction shared ordered facility/contract roster at N121 call boundary, with mutation/owner/location and exact plan oracle; alternatively event due-phase indexing only after profiling.
