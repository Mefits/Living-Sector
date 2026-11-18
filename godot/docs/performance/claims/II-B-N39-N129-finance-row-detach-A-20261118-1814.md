# Astra II-B — N129 finance row detachment
STATUS: IN_PROGRESS
OWNER: A
TIME: 2026-11-18 18:14 MSK
BASE HEAD: bedeb31e416dddb1594176ed499bee5a110f9003
SOURCE: ASTRA_FIVE_SHIFTS_RU.md II-B, deep:L129 World owned writes
TASK: Existing N129 stage shallow-copies facilities/populations dictionaries but writes nested rows; detach changed rows, avoid copying unchanged rows, preserve full Schema/N9 oracle and rollback.
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n129_finance_row_detach.gd
TEST: positive multi-transfer, negative rejected transfer, alias isolation and full-deep-copy oracle. No Actions.
