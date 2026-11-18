# Astra III/B — N38 pending recovery rollback

STATUS: IN_PROGRESS
OWNER: B
START: 2026-11-18 13:24 MSK
BASE SHA: 0e8ba1bef9df905a1a07f4552070df09f93c673a
ASTRA: III N38 save/restart atomic pending/bak, preserve verified checkpoint and old formats.
INTENDED FILES: godot/scripts/sim/save_state.gd; godot/tests/p2_perf_b_n38_pending_recovery_rollback_20261118.gd
EXPECTED: pending/previous promotion never destroys an existing primary if rename fails; valid fallback recovery; positive and negative file-state tests. No new save schema, no Actions.
