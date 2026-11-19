# Astra III — N38 pending-only survivor guard
STATUS: IN_PROGRESS
OWNER: B
START: 2026-11-19 07:21 Europe/Moscow
BASE SHA: 0c6216a260350e815122049e44328114d0c4d7d1
ASTRA: III N38 save/restart, atomic pending/bak, old receipt references, exact replay; remaining backlog N38 restart and save bytes.
INTENDED FILES: godot/scripts/sim/save_state.gd; godot/tests/p2_perf_b_n38_pending_survivor.gd
GOAL: Never overwrite an existing sole recoverable pending checkpoint before restoring it, while allowing normal saves with an independently trusted primary/backup. Positive/negative byte oracle tests.
RISK: avoid deleting/overwriting last known-good bytes; no schema or balance change.
TEST: NOT_RUN; CODE_UNVERIFIED.
