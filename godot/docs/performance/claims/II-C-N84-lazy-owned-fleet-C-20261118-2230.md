# II-C N84 lazy owned fleet
STATUS: IN_PROGRESS
OWNER: C
TIME: 2026-11-18 22:30 Europe/Moscow
BASE_SHA: 87fb8ef8d2a8e3b533688ababf16c3658f12b07a
ASTRA: II-C N84 BT/world hotpath; avoid redundant full fleet row copying while preserving owned result, N14/BT/cargo/contract semantics.
INTENDED_FILES: godot/scripts/sim/phase2/unified_ship_ai_execution.gd; godot/tests/p2_perf_c_n84_lazy_owned_fleet.gd
EXPECTED_TEST: cached vs original deep-detached fleet oracle; idle/active/contract/travel, source unchanged, output independent, invalid ship negative.
RISK: nested mutable aliases and ordered BT state; only active rows detached before BT, remaining rows detached before return.
