# Astra II-B — N39 N128 receipt history owned append
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: A
TIME: 2026-11-19 02:15 MSK
BASE_SHA: 8e90a16f7f47a0533ff69e7e5a58437c74ac91c2
TASK: remove growing deep copy of immutable N128 receipt history on each real GrantCrewXp; retain isolated ship row, full Schema/accounts oracle, rollback and alias checks.
INTENDED: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n128_receipt_owned_history.gd
TEST: legacy deep-copy oracle, duplicate command negative, failed stage no publication, external alias isolation.

CODE_SHA: 7d756617803d10e745962aa5ca9426c4819876b0
TEST_SHA: 379d76536285094bffd77f91ca2b7f6192ff808e
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED
RESULT: apply_native_n128_crew_xp now stages a detached ships root, deep-detached modified ship, and shallow detached immutable append-only N128 receipt registry. Existing receipt rows are never mutated by this path. Full Schema and N9 accounts comparison remain before atomic _world publish. Regression compares full-history oracle, sequential commands, duplicate and late reject, nested new-row alias and unchanged market/treasury.
RISK: historical receipts are shared read-only by contract; an unrelated future writer that edits old receipt nested data must detach that row first. Full N39 same-seed and N38 restart not run.
NEXT_ASTRA: II-B L129/L196 paid-tick stage — identify another actual repeated full history copy and replace only after tracing all writes and rollback boundaries, with full Schema oracle.
