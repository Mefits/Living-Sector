# Astra III / B — N38 atomic backup rotation under failure
STATUS: IN_PROGRESS
OWNER: B
STARTED: 2026-11-18 11:24 MSK
BASE_SHA: 24703402c8dbd35b4284ae7f64f80551b25ee747
SOURCE: ASTRA_FIVE_SHIFTS_RU.md — B N38 save/restart, atomic pending/bak, exact backward-compatible persistence.
SCOPE: Existing N38 v1 save_runner rotation and recovery; no vNext migration, no format changes.
INTENDED_FILES:
- godot/scripts/sim/phase2/save_state.gd (confirm actual path)
- godot/tests/p2_perf_b_n38_backup_rotation_20261118.gd
EXPECTED: preserve last known-good backup on failed primary rotation/promotion; positive save/restart and negative failure recovery.
TEST: NOT_RUN
