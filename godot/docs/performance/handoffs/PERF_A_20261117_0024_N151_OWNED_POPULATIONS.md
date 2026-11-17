# PERF A — N151 population migration owned stage (2026-11-17)

CODE COMMIT: 6df19f13c440bdc224423f8162339b93125fa55b
TEST COMMIT: d5b84b0b035ee40d286af806c327d917272a0b70
FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n151_population_owned_stage_20261117.gd

N151 migration after a nonzero moved proposal previously deep-copied all of N39 World. It now shallow-copies the root and deep-copies only populations before mutating two population rows. population_migration_last is a separately duplicated event. This preserves rollback isolation for all mutated nested population rows, while unchanged domains are read-only aliases within the candidate stage. Schema.validate, Schema.accounts, ledger restoration, conservation, and atomic publication are unchanged.

TEST EXECUTED: NOT RUN; CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No Godot execution, same-seed parity, or measured CPU benefit claimed. N151 only runs on the canonical migration interval; the change does not establish that deep:L129 snapshot calls in ships/dock_queue are improved. No CI triggered.

NEXT: run targeted negative regression plus full N151 schema/ledger oracle; measure N151 stage copy count/time, then coordinate with C to isolate repeated ship/dock world_snapshot callers without touching C-owned files. Same-seed early/late paid-tick and N38 restart parity required before accepting performance improvement.
