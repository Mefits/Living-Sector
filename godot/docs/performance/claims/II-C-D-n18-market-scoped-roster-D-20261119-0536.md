# Astra II-C D: market-scoped station staffing rosters
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: D
START: 2026-11-19 05:36 Europe/Moscow
BASE SHA: ea3837326192c96d60da3d999e2ac23022d7531d
ASTRA: II-C station/faction/market rosters; remove repeated full scans while preserving source decisions.
INTENDED FILES: godot/scripts/sim/phase2/unified_native_station_administration_phase.gd; godot/tests/p2_perf_d_n18_market_scoped_roster.gd
SCOPE: restrict temporary population and facility group aggregation to live market-owned faction/location keys, preserve sorted population/facility order, invalid market-owner failure order, due cadence, ownership and world isolation.
TEST: positive old-vs-new roster oracle; negative invalid market owner and relocation/ownership changes; NOT_RUN until Godot available.

CODE SHA: d7f726ca48fa6675149068ecc885ef526b61f12a
TEST SHA: 10067d86dcbd200f4f4c2112066dc04f1817fa4d
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED
CHANGED: N18 propose due-cycle uses _live_market_roster_keys and _market_scoped_rosters; only aggregate population and facility rows for valid market-owned faction/location keys. Keeps global assignments, sorted population/facility order, Payroll call, sorted market validation and existing error precedence. No persistent cache or World alias.
ORACLE: naive all-location totals and facility order vs scoped result, relocate/transfer/remove/install, invalid owner and detached mutation.
RISK: Godot parser and paid-tick parity not executed. Requires same-seed N18/World/N9/N38 oracle and measured paid-tick benchmark.
NEXT ASTRA II-C: Head faction capture repeated scans across factions; shared within-cycle immutable index with exact invalidation, or due event scan if profiler demonstrates cost.
