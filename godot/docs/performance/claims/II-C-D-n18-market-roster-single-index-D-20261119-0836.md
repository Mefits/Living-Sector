# II-C D — N18 due-cycle market roster single index
STATUS: IN_PROGRESS
OWNER: PERF D
START: 2026-11-19 08:36 MSK
BASE SHA: 7ec92de08a4da6dae110cae26ef49ce3a6605708
ASTRA: II-C repeated stations/markets scans, stable ordered roster with due-cycle invalidation.
INTENDED FILES: godot/scripts/sim/phase2/unified_native_station_administration_phase.gd; godot/tests/p2_perf_d_n18_market_roster_single_index.gd
GOAL: avoid repeated market traversal and global population sort by building market keys during canonical market traversal, selecting eligible populations before ordering; preserve error precedence, owner/market decisions, assignments and no cross-tick cache.
TEST: positive original-order oracle, negative invalid owner, relocation, changed faction, duplicate/population ordering. NOT_RUN until actual Godot execution.
