# Astra II-C / D — Head planner capture and global scans

STATUS: IN_PROGRESS
OWNER: D
START: 2026-11-18 11:42 MSK
BASE HEAD: 2bfd909c3b4607bea7478f9fdc9f773c9c2aea79
SOURCE: ASTRA_FIVE_SHIFTS_RU.md → II-C station/faction/market rosters (D), Head faction read views and repeated full scans.
SCOPE: Avoid global faction capture for Head proposals with no actionable source stock goal; preserve exact invalid head/mode ordering and snapshot semantics; reduce repeated global scans on live planning path.
INTENDED FILES: godot/scripts/sim/phase2/unified_native_hybrid_planning.gd; godot/tests/p2_perf_d_head_capture_goal_gate.gd
EXPECTED CHECK: positive valid goal parity, negative no-goal/invalid-world/mode/other-domain, ownership, no RNG or budget changes. TEST NOT RUN pending Godot.
