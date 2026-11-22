# Astra II-B · N39 N151 migration owned rows
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: A
START: 2026-11-19 04:10 MSK
BASE FILE SHA: e5eb4fd1efe2311c9c6c998ec0077f3b20064f43
TASK: N39 L129/L196 deep snapshot elimination via owned-write stage, rollback/alias and full Schema oracle.
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n151_migration_owned_rows.gd
SCOPE: preserve N151 paid migration, N9 ledger, full Schema, no alias leak on rejection; shallow population registry and detach only source/destination rows.
TEST: positive legacy deep-copy oracle; negative mutation/rollback, no-op.

CODE SHA: 32e62066849ff98272e1f0ff1dfed691027ea76d
TEST SHA: 5b0ee36399c873bc3a7bbfb15e81a118f6ad1d63
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED.
IMPLEMENTED: apply_native_population_migration now uses _n151_owned_migration_stage. The stage shallow-copies the World and population registry, deeply detaches both migrant households, and leaves unrelated rows unchanged. No changes to N9 transfer, conservation, full Schema oracle, account reconciliation, or atomic World+ledger commit.
NEGATIVE: missing/identical IDs, malformed household, invalid staged wealth and authoritative rollback; positive legacy deep-copy comparator and nested alias isolation.
RISK: full paid-tick N151 and N38 restart parity not run; no measured speedup.
NEXT ASTRA II-B: remaining N39 L129/L196 paid construction escrow or N39 operating-world stage with real callsite ownership, full Schema oracle, negative rollback and same-seed parity.
