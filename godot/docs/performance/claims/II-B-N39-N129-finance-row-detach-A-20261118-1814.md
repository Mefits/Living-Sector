# Astra II-B — N129 finance row detachment
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: A
TIME: 2026-11-18 18:14 MSK
BASE HEAD: bedeb31e416dddb1594176ed499bee5a110f9003
SOURCE: ASTRA_FIVE_SHIFTS_RU.md II-B, deep:L129 World owned writes
TASK: Existing N129 stage shallow-copies facilities/populations dictionaries but writes nested rows; detach changed rows, avoid copying unchanged rows, preserve full Schema/N9 oracle and rollback.
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n129_finance_row_detach.gd
TEST: positive multi-transfer, negative rejected transfer, alias isolation and full-deep-copy oracle. No Actions.

## Result
CODE SHA: be3afa2e6c560a563c28b3bd46d86d959ef42bfa
TEST SHA: 2e7d6926032146e96f6ec9cb7d501265a3f0eeea
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED
SOURCE: n39_native_world_production.gd apply_native_faction_finance: N129 shallow domain stages now deep-detach only rows with changed credits/wealth, including nested data, before dirty flag writes. Full Schema/accounts/N9 checks and commit remain unchanged. Unchanged rows remain read-only aliases in the stage; do not mutate them.
NEGATIVES: missing/wrong population roster, late rejection after staged facility updates, nested changed-row isolation, no-op flags, deep-copy oracle (model regression; not production invocation).
NEXT: Astra II-B deep:L129 repeated World snapshots by caller, coordinate ship/dock callsite with C, preserve N38 same-seed exact parity. No Actions until user-approved testing.
