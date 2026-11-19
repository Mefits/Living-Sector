# Astra II-B · N39 N151 migration owned rows
STATUS: IN_PROGRESS
OWNER: A
START: 2026-11-19 04:10 MSK
BASE FILE SHA: e5eb4fd1efe2311c9c6c998ec0077f3b20064f43
TASK: N39 L129/L196 deep snapshot elimination via owned-write stage, rollback/alias and full Schema oracle.
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n151_migration_owned_rows.gd
SCOPE: preserve N151 paid migration, N9 ledger, full Schema, no alias leak on rejection; shallow population registry and detach only source/destination rows.
TEST: positive legacy deep-copy oracle; negative mutation/rollback, no-op.
