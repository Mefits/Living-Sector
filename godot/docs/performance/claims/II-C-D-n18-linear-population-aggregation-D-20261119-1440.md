# Astra II-C / D — N18 linear population aggregation
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: PERF D
START: 2026-11-19 14:40 MSK
BASE FILE SHA: 2a01f920935ff0b30a088b8b8a2f1c8bab63f65f
BRANCH: integration/perf-astra-5-workers-20261116
TASK: D stations/factions repeated scans — remove full sorted population roster and redundant per-population grouping on N18 due cycle, preserving exact workforce totals, owner and market error precedence.
INTENDED FILES: godot/scripts/sim/phase2/unified_native_station_administration_phase.gd; godot/tests/p2_perf_d_n18_linear_population_oracle.gd
CHECK: naive sorted original vs new grouping; insertion order, ownership/location changes, malformed market, integer workforce truncation, no mutable alias.

CODE SHA: 9083f760dcba8d35660d1b4ad5a0f18ed389ecf0
TEST SHA: 87607ed9d67b829408423baa079b2519b0629cd1
TEST: NOT_RUN (Godot not executed); CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED
SOURCE: _market_scoped_rosters now accumulates population totals directly, preserving row type check, per-row integer truncation, market-key filtering and independent output dictionaries. Facility roster remains in original sorted order. No cross-tick state or new World alias.
ORACLE: 1500 population rows, original sorted aggregation, ownership transfer, relocation, removed market, invalid market owner, fractional workforce and mutation isolation.
RISK: Godot parser/runtime and true paid tick speedup not measured. Integer accumulation assumes valid source counts and no overflow, matching existing semantics.
NEXT ASTRA II-C: Head/N121 repeated cross-faction facility/contract scans; establish caller-cycle read view and invalidation with malformed market-owner oracle.
