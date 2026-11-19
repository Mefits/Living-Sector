# Astra III/B — N38 interrupted recovery-displaced reconciliation

STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: B
TIME: 2026-11-18 16:21 Europe/Moscow
BASE HEAD: 19b962b9bf6619622a15d7d0d17981ee44dd7f33
ASTRA: III N38 persistence/restart, atomic pending/bak recovery and backward compatibility.
FILES: godot/scripts/sim/save_state.gd; godot/tests/p2_perf_b_n38_displaced_recovery_20261118.gd
GOAL: reconcile a leftover .recovery-displaced after interrupted promotion, without discarding a sole verified recovery checkpoint; retain primary precedence and protect rollback.
TEST: positive valid primary+orphan, corrupt primary+valid orphan, invalid orphan, promotion failure, repeated recovery. No Actions.

RESULT: Reconcile a stale .recovery-displaced only when primary is trusted; preserve invalid-primary orphan, allow recovery of displaced candidate by parking rejected original separately, add .recovery-rejected as last-chance load candidate. Reconciliation is wired into real save_runner; successful restore of primary cleans displaced orphan, successful restore of displaced attempts promotion. No N38 format or economy change.
CODE SHA: e7c0b8f93ab59df3300e42cbb009e4cbf847798d; cb43c34b0de875cbaa9e70b5347888ab18280283
TEST SHA: 4af6b5977f38882df9f165cca5b04e249ce68f60
TEST: NOT_RUN (Godot runtime not executed). PERFORMANCE: NOT_MEASURED.
RISK: filesystem rename error injection and full Runner save/restart oracle remain untested; do not treat as accepted until real headless/Windows tests.
NEXT ASTRA: II-A N9 real paid receipt COW shard-copy costs vs 100/300/600/900 paid ticks, then N38 restart/encoded-size growth oracle.
