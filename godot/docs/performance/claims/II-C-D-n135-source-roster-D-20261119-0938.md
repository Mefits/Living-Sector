# Astra II-C D — N135 ordered source roster
STATUS: IN_PROGRESS
OWNER: D
START: 2026-11-19 09:38 MSK
BASE_SHA: 1c05311ba7558f999bd38b9e9a7b60bba0ce7e4d
ASTRA: II-C station/faction/market rosters; eliminate repeated full market scans.
FILES: godot/scripts/sim/phase2/unified_station_demand_phase.gd; godot/tests/p2_perf_d_n135_source_roster.gd
PLAN: Build a single ordered eligible supplier roster for each N135 propose call, retaining original per-deficit stock, reservation, price and overflow checks and source order. Add legacy oracle and negative cases for invalid owner/stock, changed market and multiple competing destinations.
RISK: deterministic order and first-error parity; no persistent cache, no money/stock movement.
TEST: NOT_RUN
