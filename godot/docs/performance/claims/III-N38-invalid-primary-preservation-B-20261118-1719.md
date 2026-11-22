# Astra III/B — preserve invalid primary during verified pending promotion

STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: B
START: 2026-11-18 17:19 MSK
BASE SHA: 971c1df9e337275af4a75b3e0875a4cd46de7c2a
ASTRA: III N38 atomic pending/bak, backward-compatible restart and rollback
CODE SHA: a6da2749d4affa06a93d0b6dd734824287a020e4
TEST SHA: b881b82f77bbea34c29c850700108684cd029636
FILES:
- godot/scripts/sim/save_state.gd
- godot/tests/p2_perf_b_n38_invalid_primary_promotion.gd

RESULT: The actual _promote_verified_pending invalid-primary path now parks the old primary in the existing .recovery-rejected candidate rather than deleting it before rename. A pre-existing rejected checkpoint blocks destructive collision. Failed pending promotion attempts to restore the old primary; if rollback itself fails, original bytes remain parked. The healthy-primary .bak rotation remains unchanged. Existing load_runner already considers .recovery-rejected, so this uses the existing restart recovery path and N38 v1 format.
TEST: NOT_RUN (no Godot execution; no Actions by user instruction). Targeted positive/negative test covers successful invalid-primary promotion, rejected-file collision, missing pending with rollback, and healthy-primary backup rotation. File bytes are compared directly.
RISK: Platform-specific rename failure behavior and full Runner restore/restart remain unverified. No performance claim.
NEXT ASTRA: II-A real N9 receipt shard copy cost and opt-in parity against default COW on late-tick same-seed paid transactions; III N38 full restart/rollback validation.
