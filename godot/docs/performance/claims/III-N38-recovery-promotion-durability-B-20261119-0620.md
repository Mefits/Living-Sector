# Astra III — N38 recovery promotion durability and restart
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: B
TIME: 2026-11-19 06:20 MSK
BASE HEAD: d228fd4edfd3fad8bda0956c1523e5049993fd75
SOURCE: ASTRA_FIVE_SHIFTS_RU.md — B N38 save/restart, atomic pending/bak, recovery integrity
FILES: godot/scripts/sim/save_state.gd; godot/tests/p2_perf_b_n38_recovery_promotion_durability.gd
GOAL: preserve recoverable candidate on failed promotion; report persistence status independently of live restore; test success, collision, crash/restart and byte-preservation oracle.
TEST: NOT_RUN

CODE SHA: e9736ef938a5c707f405a659ef475213a38b1f94
TEST SHA: b419a070dcfbac7daee05c3b395249f69666cf62
CHANGED: _promote_recovered_checkpoint now validates the installed primary with N38 trusted preflight before discarding its predecessor, and attempts reversible rollback of failed post-rename verification. load_runner exposes promoted_displaced, promotion_attempted, restart_safe and persistence_warning, distinguishing live recovery from durable restart readiness.
TEST COVERAGE: negative invalid candidate with/without primary; orphan/rejected collisions; byte-for-byte preservation; positive no-orphan no-op. Full real-Runner positive restore and interruption injection still pending.
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED.
RISKS: filesystem rollback rename itself may fail; recovery candidates remain on disk. Actual restart safety requires Windows Godot run. No format/balance/clock changes.
NEXT: Astra III N38 real Runner save/restart positive acceptance, successful orphan promotion, repeated crash/restart; then encoded-size scaling at 100/300/600/900 paid ticks.
