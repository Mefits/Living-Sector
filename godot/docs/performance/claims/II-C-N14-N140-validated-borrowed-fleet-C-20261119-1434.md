# II-C N14/N140 validated borrowed fleet — C
STATUS: IN_PROGRESS
OWNER: C
START: 2026-11-19 14:34 MSK
BASE SHA: b6265a71e4a6b65755dd61a56c8e38200f198b80
ASTRA: II-C ship/contract/dock/route caches; remove redundant N14/N140 ship deep copies while retaining exact ShipState restore validation.
INTENDED FILES: godot/scripts/sim/ship_state.gd; godot/scripts/sim/phase2/unified_ship_phase.gd; godot/tests/p2_perf_c_n14_borrowed_restore_oracle.gd
EXPECTED: validated borrowed records only for advance preflight, N140 detached ownership before motion, depart remains deep-owned; positive/negative oracle incl invalid cargo/fitting/transit and alias checks.
TEST: NOT_RUN
