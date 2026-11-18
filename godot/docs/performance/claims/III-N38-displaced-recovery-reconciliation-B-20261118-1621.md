# Astra III/B — N38 interrupted recovery-displaced reconciliation

STATUS: IN_PROGRESS
OWNER: B
TIME: 2026-11-18 16:21 Europe/Moscow
BASE HEAD: 19b962b9bf6619622a15d7d0d17981ee44dd7f33
ASTRA: III N38 persistence/restart, atomic pending/bak recovery and backward compatibility.
FILES: godot/scripts/sim/save_state.gd; godot/tests/p2_perf_b_n38_displaced_recovery_20261118.gd
GOAL: reconcile a leftover .recovery-displaced after interrupted promotion, without discarding a sole verified recovery checkpoint; retain primary precedence and protect rollback.
TEST: positive valid primary+orphan, corrupt primary+valid orphan, invalid orphan, promotion failure, repeated recovery. No Actions.
