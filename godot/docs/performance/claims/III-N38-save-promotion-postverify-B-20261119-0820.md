# Astra III — N38 save promotion post-rename verification
STATUS: IN_PROGRESS
OWNER: B
START: 2026-11-19 08:20 MSK
BASE SHA: f18ba863cbe389723d89f3e3f3fbfdb083d8d71a
ASTRA: III N38 atomic pending/bak save/restart, authenticated checkpoint and rollback
FILES: godot/scripts/sim/save_state.gd; godot/tests/p2_perf_b_n38_postpromotion_check.gd
GOAL: verify the installed primary after pending promotion, preserve backup/previous on failed verification, and cover positive and negative recovery paths without changing envelope format.
TEST: Godot targeted headless, positive save and tampered/failed post-promotion oracle; TEST_NOT_RUN pending manual run.
