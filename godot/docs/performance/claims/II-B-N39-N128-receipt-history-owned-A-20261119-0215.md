# Astra II-B — N39 N128 receipt history owned append
STATUS: IN_PROGRESS
OWNER: A
TIME: 2026-11-19 02:15 MSK
BASE_SHA: 8e90a16f7f47a0533ff69e7e5a58437c74ac91c2
TASK: remove growing deep copy of immutable N128 receipt history on each real GrantCrewXp; retain isolated ship row, full Schema/accounts oracle, rollback and alias checks.
INTENDED: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n128_receipt_owned_history.gd
TEST: legacy deep-copy oracle, duplicate command negative, failed stage no publication, external alias isolation.
