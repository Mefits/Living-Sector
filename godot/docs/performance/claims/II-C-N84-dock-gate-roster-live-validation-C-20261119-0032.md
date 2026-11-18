# II-C N84 dock/gate roster live validation
STATUS: IN_PROGRESS
OWNER: C
START: 2026-11-19 00:32 MSK
BASE SHA: 0f069eda7ae45637f47e13f3ae169d584f1e098d
ASTRA: II-C ship/dock paid-tick hotpath, indexed dock occupancy/gate/shipyard with stable tie-break and invalidation.
INTENDED FILES: godot/scripts/sim/phase2/unified_ship_ai_execution.gd; godot/tests/p2_perf_c_n84_dock_gate_roster_oracle.gd
GOAL: make proposal-local gate and shipyard roster robust to live mutations, avoid scratch namespace collision and repeated scans, preserve original command and failure ordering.
TEST: positive and negative cached-vs-uncached gate and shipyard availability, mutation and stale roster scenarios; NOT_RUN until Godot available.
