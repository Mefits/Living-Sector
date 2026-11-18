# II-C N84 passenger colony dock candidate indexing
STATUS: IN_PROGRESS
OWNER: C
START: 2026-11-18 18:27 MSK
BASE SHA: 3fac0a32cc967d682dc636d4bd689f459e5d2953
ASTRA: II-C ships+dock_queue repeated full scans, preserve source-order tie-break and paid physical dock semantics.
INTENDED FILES: godot/scripts/sim/phase2/unified_ship_ai_execution.gd; godot/tests/p2_perf_c_n84_passenger_dock_index.gd
EXPECTED: call-scoped passenger site candidate roster; unchanged construction direct lookup, receipt/facility live validation, positive/negative original-scan oracle, no cross-tick cache.
TEST: NOT_RUN
