# II-C N84 dock/gate roster live validation
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: C
START: 2026-11-19 00:32 MSK
BASE SHA: 0f069eda7ae45637f47e13f3ae169d584f1e098d
ASTRA: II-C ship/dock paid-tick hotpath, indexed dock occupancy/gate/shipyard with stable tie-break and invalidation.
INTENDED FILES: godot/scripts/sim/phase2/unified_ship_ai_execution.gd; godot/tests/p2_perf_c_n84_dock_gate_roster_oracle.gd
GOAL: make proposal-local gate and shipyard roster robust to live mutations, avoid scratch namespace collision and repeated scans, preserve original command and failure ordering.
TEST: positive and negative cached-vs-uncached gate and shipyard availability, mutation and stale roster scenarios; NOT_RUN until Godot available.

CODE SHA: 6205fb0f30d1a4dc24b200f5c2e9a344c6db3957
TEST SHA: a3ac9b78de1e04d8503b880b60acefae3c30d2ff
TEST: NOT_RUN / CODE_UNVERIFIED / PERFORMANCE_NOT_MEASURED
FILES: godot/scripts/sim/phase2/unified_ship_ai_execution.gd; godot/tests/p2_perf_c_n84_dock_gate_roster_oracle.gd
RESULT: shipyard candidate roster moved to a private nested namespace (no collision with real location "_ready"); rechecks live yard type/location/abandoned before N21 RequestDock. Gate candidate list now rechecks live type/location/link before GateJump command. Both remain proposal-local; no persistent World or N38 cache, no N9/N39 changes.
NEGATIVES: empty shipyard, location collision, abandoned/moved yard, invalidated gate type/location; cached vs fresh decision and command payload.
LIMITATION: Newly inserted facilities during the same synchronous propose() are not reflected by a prebuilt roster; N84 never adds facilities in this phase. No paid-tick or full BT/cargo parity benchmark yet.
NEXT ASTRA II-C: N84 dock occupancy and N153 contract candidate hotpaths; test paid 24/100/500 ship decisions/BT/cargo/fuel/route with same-seed oracle.
