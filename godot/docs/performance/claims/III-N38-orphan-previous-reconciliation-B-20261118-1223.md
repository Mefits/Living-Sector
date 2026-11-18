# Astra III/B — N38 interrupted backup rotation recovery
STATUS: IN_PROGRESS
OWNER: B
START: 2026-11-18 12:23 Europe/Moscow
BASE HEAD: 2726ae353514cc160b69d73ce18b501e04d72055
ASTRA BACKLOG: III — N38 persistence/save-restart and crash-safe atomic pending/bak; compatible old save formats.
SCOPE: Existing N38 v1 rotation leaves .bak.previous orphan after interruption; next save refuses indefinitely. Reconcile orphan only after validating primary and backup, preserve rollback copies on failure. Ensure pending recovery does not destroy the only good checkpoint.
INTENDED FILES: godot/scripts/sim/save_state.gd; godot/tests/p2_perf_b_n38_orphan_rotation_20261118.gd
TEST PLAN: positive interrupted rotation recovery with valid primary/backup; negative invalid primary/backup and pending promotion failure, old save intact; no Godot/CI available, TEST_NOT_RUN until acceptance.
