# II-C — N84 active-row read-only gates
STATUS: IN_PROGRESS
OWNER: C
START: 2026-11-19 01:30 MSK
BASE SHA: 8210dcd94b6470ee3a1b819a9d478a17bed5b0e4
ASTRA: II-C ship/BT owned boundary; eliminate unnecessary deep copies on N84 active failure paths while preserving N104 validation and BT error priority.
INTENDED FILES: godot/scripts/sim/phase2/unified_ship_ai_execution.gd; godot/tests/p2_perf_c_n84_readonly_gates.gd
TEST: positive/negative oracle for invalid obligation, invalid BT, active row ownership and mutation isolation.
