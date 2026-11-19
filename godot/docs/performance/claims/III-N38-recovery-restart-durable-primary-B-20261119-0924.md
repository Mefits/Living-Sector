# Astra III / B — N38 restart durability after recovery
STATUS: IN_PROGRESS
OWNER: B
START: 2026-11-19 09:24 MSK
BASE SHA: 501195e7bb4030145f0e8a96292b81165ee03553
ASTRA: III N38 compatible save/restart, atomic pending/bak and exact checkpoint preservation.
SCOPE: godot/scripts/sim/save_state.gd; godot/tests/p2_perf_b_n38_recovery_restart_durability.gd
GOAL: do not report restart-safe when a successfully restored primary still has unresolved recovery orphan or when promoted primary lacks exact source checkpoint equivalence; preserve diagnostic/recovery bytes on failure.
TEST: positive successful restart, negative invalid promoted primary and interrupted orphan, oracle exact checkpoint.
RISK: filesystem rename/rollback and preserving accepted Runner state; no archive format change.
