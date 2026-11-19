# Astra II-C D: market-scoped station staffing rosters
STATUS: IN_PROGRESS
OWNER: D
START: 2026-11-19 05:36 Europe/Moscow
BASE SHA: ea3837326192c96d60da3d999e2ac23022d7531d
ASTRA: II-C station/faction/market rosters; remove repeated full scans while preserving source decisions.
INTENDED FILES: godot/scripts/sim/phase2/unified_native_station_administration_phase.gd; godot/tests/p2_perf_d_n18_market_scoped_roster.gd
SCOPE: restrict temporary population and facility group aggregation to live market-owned faction/location keys, preserve sorted population/facility order, invalid market-owner failure order, due cadence, ownership and world isolation.
TEST: positive old-vs-new roster oracle; negative invalid market owner and relocation/ownership changes; NOT_RUN until Godot available.
