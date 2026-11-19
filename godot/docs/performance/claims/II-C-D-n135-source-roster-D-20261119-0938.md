# Astra II-C D — N135 ordered source roster
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: D
START: 2026-11-19 09:38 MSK
BASE_SHA: 1c05311ba7558f999bd38b9e9a7b60bba0ce7e4d
ASTRA: II-C station/faction/market rosters; remove repeated full market scans.
CODE_SHA: 3f3145b3141a1725f76f251a2d2b3eabcd136822
TEST_SHA: a7e777c18b1b36ab6fd7a231d8a37c4d36242ffc
TEST: NOT_RUN
CODE: UNVERIFIED
PERFORMANCE: NOT_MEASURED
FILES:
- godot/scripts/sim/phase2/unified_station_demand_phase.gd
- godot/tests/p2_perf_d_n135_source_roster.gd
RESULT: N135 propose constructs one sorted, capture-local valid supplier roster and reuses it across all destination/commodity deficits. Replaces repeated markets.keys()+sort() and owner/location eligibility checks in each deficit. Physical stock, reservations, prices, affordability, overflow and exact proposal rows remain evaluated in original order on each deficit. No persistent cache or mutable World copy.
ORACLE: independent naive per-deficit full registry scan; two competing destinations, moved supplier owner, removed market, changed stock, invalid destination owner, negative supplier stock, and World alias checks.
RISK: Godot execution and full parity not yet run. No GitHub Actions per user.
NEXT: Astra II-C — repeated Head faction captures/contract-board scans across heads, with a single-cycle borrowed read-view and ownership/status change oracle; otherwise next D-owned due-event hotpath.
