# Astra II-C / D — N18 linear population aggregation
STATUS: IN_PROGRESS
OWNER: PERF D
START: 2026-11-19 14:40 MSK
BASE FILE SHA: 2a01f920935ff0b30a088b8b8a2f1c8bab63f65f
BRANCH: integration/perf-astra-5-workers-20261116
TASK: D stations/factions repeated scans — remove full sorted population roster and redundant per-population grouping on N18 due cycle, preserving exact workforce totals, owner and market error precedence.
INTENDED FILES: godot/scripts/sim/phase2/unified_native_station_administration_phase.gd; godot/tests/p2_perf_d_n18_linear_population_oracle.gd
CHECK: naive sorted original vs new grouping; insertion order, ownership/location changes, malformed market, integer workforce truncation, no mutable alias.
