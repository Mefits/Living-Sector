# II-C D — N18 due-cycle market roster single index
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: PERF D
START: 2026-11-19 08:36 MSK
BASE SHA: 7ec92de08a4da6dae110cae26ef49ce3a6605708
ASTRA: II-C stations/markets repeated full scans and stable ordered roster.
CODE SHA: 989387ef9bfe1af89ffbf2928ea60237de6f15a5 (initial 6cf6d6f879b1dfd01b95a4c906733b7f606d7d55)
TEST SHA: 687d498236ca0e5c2a5277809d38ba9d7b1657f3
FILES: godot/scripts/sim/phase2/unified_native_station_administration_phase.gd; godot/tests/p2_perf_d_n18_market_roster_single_index.gd
IMPLEMENTED: due N18 propose sorts market locations once and reuses that order for market-key construction and canonical planning loop. _market_scoped_rosters scans all population rows for source typing but sorts only populations belonging to eligible station-market keys, preserving ID order and per-row workforce rounding. Existing helper calls remain supported. Roster remains local to a single synchronous proposal; next call observes mutations.
ORACLE: 120 facilities, 1200 populations; compare against full sorted population/market oracle; negative invalid owner; market removal, station type, owner/faction, relocation, population relocation, alias checks.
TEST: NOT_RUN
CODE: CODE_UNVERIFIED
PERFORMANCE: NOT_MEASURED
RISK: No runtime parser or paid-tick A/B executed; validate with Godot 4.7.2 before acceptance. No change to World/N9/N38, payroll, assignment ordering or balance.
NEXT ASTRA II-C: Head/faction repeated contract and facility scans across same paid tick; find actual multi-Head caller and implement bounded borrowed index with mutation invalidation and exact decision oracle.
