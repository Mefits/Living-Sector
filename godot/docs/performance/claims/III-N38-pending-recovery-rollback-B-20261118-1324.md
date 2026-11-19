# Astra III/B — N38 pending recovery rollback

STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: B
START: 2026-11-18 13:24 MSK
BASE SHA: 0e8ba1bef9df905a1a07f4552070df09f93c673a
ASTRA: III N38 save/restart atomic pending/bak, preserve verified checkpoint and old formats.
INTENDED FILES: godot/scripts/sim/save_state.gd; godot/tests/p2_perf_b_n38_pending_recovery_rollback_20261118.gd
EXPECTED: pending/previous promotion never destroys an existing primary if rename fails; valid fallback recovery; positive and negative file-state tests. No new save schema, no Actions.

CODE SHA: 6e9cbf12031ceafece0c26262754eb6302578990
TEST SHA: 01dc23a707618ae966a005fb086aca85c5180fa5
TEST: NOT_RUN (no local Godot; Actions deliberately not started)
FILES: godot/scripts/sim/save_state.gd; godot/tests/p2_perf_b_n38_pending_recovery_rollback_20261118.gd
IMPLEMENTED: load_runner recovery of pending/previous now uses _promote_recovered_checkpoint, parks existing primary rather than deleting it, restores parked primary on failed rename, includes interrupted recovery displaced checkpoint in load fallback. Preserves .bak and N38 v1.
TEST COVERAGE: positive pending/previous promotion, absent primary, missing candidate, orphan collision preserving all files. Runtime N38 exact restart/parity remains unverified.
PERFORMANCE: NOT_MEASURED; safety fix, not a claim of faster paid ticks.
NEXT ASTRA: II-A N9 measured receipt growth and shard copy/immutable provenance parity; III N38 restart and save-size window with real Godot runtime.
