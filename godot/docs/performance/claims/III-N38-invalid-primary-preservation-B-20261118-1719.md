# Astra III/B — preserve invalid primary during verified pending promotion

STATUS: IN_PROGRESS
OWNER: B
START: 2026-11-18 17:19 MSK
BASE SHA: 971c1df9e337275af4a75b3e0875a4cd46de7c2a
ASTRA: III N38 atomic pending/bak, backward-compatible restart and rollback
INTENDED FILES: godot/scripts/sim/save_state.gd; godot/tests/p2_perf_b_n38_invalid_primary_promotion.gd
GOAL: replace destructive invalid-primary removal with collision-safe parking and rollback; exercise success, promotion failure, preserved rejected checkpoint and collision negatives.
TEST: NOT_RUN
