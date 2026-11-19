# Astra III / B — N38 restart durability after recovery
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: B
START: 2026-11-19 09:24 MSK
BASE SHA: 501195e7bb4030145f0e8a96292b81165ee03553
ASTRA: III N38 compatible save/restart, atomic pending/bak and exact checkpoint preservation.
SCOPE: godot/scripts/sim/save_state.gd; godot/tests/p2_perf_b_n38_recovery_restart_durability.gd
GOAL: do not report restart-safe when a successfully restored primary still has unresolved recovery orphan or when promoted primary lacks exact source checkpoint equivalence; preserve diagnostic/recovery bytes on failure.
TEST: positive successful restart, negative invalid promoted primary and interrupted orphan, oracle exact checkpoint.
RISK: filesystem rename/rollback and preserving accepted Runner state; no archive format change.

CODE SHA: f5ab3be60ca3d2d8d10261dec0285d88b0af3697
TEST SHA: 39be4ac157f105521e7372b120f6ae22573d18d8
TEST: NOT_RUN / CODE_UNVERIFIED / PERFORMANCE_NOT_MEASURED
CHANGED: save_state.gd _promote_recovered_checkpoint() preserves displaced original until a second real Runner restore; load_runner() propagates orphan cleanup failure into restart_safe, persistence_warning and recovery_cleanup_error. No N38 schema change.
TEST CASES: valid authenticated pending promotion, byte-for-byte displaced preservation, denied cleanup without Runner acceptance, second load_runner cleanup and checkpoint oracle, competing orphan collision.
RISK: Godot parser/runtime and native coherence fixture not executed; full real TickRunner paid-tick parity still required.
NEXT ASTRA: II-A N9 measured receipts/provenance growth and exact paid transaction oracle; III real TickRunner save/restart on paid ticks 100/300/600/900.
