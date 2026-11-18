# Astra III/B — N38 interrupted backup rotation recovery
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: B
START: 2026-11-18 12:23 Europe/Moscow
BASE HEAD: 2726ae353514cc160b69d73ce18b501e04d72055
ASTRA BACKLOG: III — N38 persistence/save-restart and crash-safe atomic pending/bak; compatible old save formats.
SCOPE: Existing N38 v1 rotation leaves .bak.previous orphan after interruption; next save refuses indefinitely. Reconcile orphan only after validating primary and backup, preserve rollback copies on failure. Ensure pending recovery does not destroy the only good checkpoint.
INTENDED FILES: godot/scripts/sim/save_state.gd; godot/tests/p2_perf_b_n38_orphan_rotation_20261118.gd
TEST PLAN: positive interrupted rotation recovery with valid primary/backup; negative invalid primary/backup and pending promotion failure, old save intact; no Godot/CI available, TEST_NOT_RUN until acceptance.

## Completed
CODE SHA: 5ea6ee42c0a7ab6e6e48d31c9defb8335869b278
TEST SHA: 639ff43411aa1d0daf7ad57cbe339bde04b49c78
TEST: NOT_RUN (Godot runtime not invoked; no GitHub Actions)
FILES: godot/scripts/sim/save_state.gd; godot/tests/p2_perf_b_n38_orphan_rotation_20261118.gd
CALLSITES: save_runner after pending verification and before _promote_verified_pending; new _reconcile_parked_backup.
FIX: validate both recovery candidates with existing N38 preflight; retain valid .bak, recover valid .bak.previous when .bak is bad, remove invalid orphans only with a verified primary, fail closed if all candidates are invalid. Avoid indefinitely blocking the next save after interrupted rotation. Original N38 envelope, size budget, pending write, source cadence and ledger untouched.
POSITIVE: valid backup wins; verified parked backup replaces corrupt backup; valid primary permits removal of corrupt backups.
NEGATIVE: no trusted candidate retains all bytes; absent pending promotion rolls back primary/backup.
LIMITATIONS: CODE_UNVERIFIED; helper unit tests use explicitly supplied trust flags while production computes them via _trusted_for_backup_rotation; full runner save/restart and Windows crash-injection remain untested.
PERFORMANCE: NOT_MEASURED; safety/restart improvement only.
NEXT ASTRA: II-A N9 receipts/history growth — compare existing paid-path append/snapshot profile at tick100/300/600/900, then implement only demonstrated B-owned transaction overlay/copy reduction with exact N38 parity.
