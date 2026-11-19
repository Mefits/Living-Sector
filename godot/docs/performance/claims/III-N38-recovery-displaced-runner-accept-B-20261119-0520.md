# Astra III — N38 recovery-displaced restart integrity
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: B
TIME: 2026-11-19 05:20 MSK
BASE HEAD: a3027cdd18b2d7f0cce14a8e676d80180c7594a4
SOURCE: ASTRA_FIVE_SHIFTS_RU.md B N38 save/restart recovery
CODE SHA: b788000251ee84b1c65e951ff1ec5c3e49791d90
TEST SHA: 0a0a6b2ef1ad726ecc9dc35d9ebad13c427946b4
FILES: godot/scripts/sim/save_state.gd; godot/tests/test_n38_recovery_displaced_runner_accept.gd
CHANGED: save_runner now refuses to rotate when an unresolved .recovery-displaced orphan exists (ERR_BUSY). _reconcile_recovery_displaced now requires explicit successful live Runner acceptance and trusted primary preflight before deleting the orphan; load_runner passes acceptance only after restore_checkpoint succeeds.
INVARIANTS: no orphan loss on failed restore, corrupt primary, missing primary, or interrupted recovery; no change to checkpoint format, tick semantics, or N9.
TEST: NOT_RUN (Godot/Windows manual testing deferred); CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED.
TEST COVERAGE: no-orphan positive, missing-primary negative, corrupt-primary negative, orphan-byte preservation oracle. Full valid-primary load/save/restart integration remains to run.
NEXT: Astra III — end-to-end N38 save/restart with real Runner restore, verified orphan cleanup, crash during promotion and repeated restart; check growing checkpoint size.
