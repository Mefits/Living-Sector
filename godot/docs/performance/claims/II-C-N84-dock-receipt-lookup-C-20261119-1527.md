# II-C N84 dock receipt lookup
STATUS: IN_PROGRESS
OWNER: C
START: 2026-11-19 15:27 Europe/Moscow
BASE SHA: b3a70728e3f032ad820af24338953c96f2f9f420
ASTRA: II-C fleet/contracts/dock hotpaths; reduce repeated dock receipt materialization, preserve exact DockDwell semantics.
INTENDED FILES: godot/scripts/sim/phase2/unified_ship_ai_execution.gd; godot/tests/p2_perf_c_n84_dock_receipt_lookup.gd
TEST: independent latest-dock receipt oracle, multiple ships, malformed/non-dock receipts, fresh proposal invalidation, BT DockDwell boundary.
RISKS: receipt iteration order and live authoritative N21 proof; never cache across paid ticks.
