# Astra III — N38 recovery promotion durability and restart
STATUS: IN_PROGRESS
OWNER: B
TIME: 2026-11-19 06:20 MSK
BASE HEAD: d228fd4edfd3fad8bda0956c1523e5049993fd75
SOURCE: ASTRA_FIVE_SHIFTS_RU.md — B N38 save/restart, atomic pending/bak, recovery integrity
FILES: godot/scripts/sim/save_state.gd; godot/tests/p2_perf_b_n38_recovery_promotion_durability.gd
GOAL: preserve recoverable candidate on failed promotion; report persistence status independently of live restore; test success, collision, crash/restart and byte-preservation oracle.
TEST: NOT_RUN
