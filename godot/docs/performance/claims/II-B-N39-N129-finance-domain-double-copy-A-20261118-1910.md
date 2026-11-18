# Astra II-B — N129 finance domain double-copy
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: A
START: 2026-11-18 19:10 MSK
BASE HEAD: 40c821317e1fb4d23f5c08b74fd58e78c137a8b5
SOURCE: ASTRA_FIVE_SHIFTS_RU.md II-B bounded owned write sets / alias rollback / Schema oracle
TASK: Remove redundant full deep copies of facilities/populations in active N129 finance stage, preserve exact account roster, ledger and failure isolation.
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n129_finance_domain_owned.gd
EXPECTED CHECK: positive multi-wallet same-seed deep-copy oracle; negative missing roster, no-op, nested alias and rejected transfer; Schema/N9 parity. No Actions.

RESULT: Active apply_native_faction_finance now shallow-copies scalar treasury and facility/population registries, deep-detaching only changed wallet rows. Avoids the previous full deep-copy of both growing registries followed by redundant row copies. No change to N9 fork/transfers, Schema.validate/accounts, roster checks, or atomic commit.
CODE SHA: 4a9b2053032234d48a385085b2edd431ac314659
TEST SHA: 7ff421532c265c58faeabbef3021264fad966f0d
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED. Test compares old full-domain vs owned stage, changed nested aliases, rejected/missing rosters, no-op. This is a model test; production integration and full Schema/N9/N38 same-seed oracle remain pending.
NEXT ASTRA II-B: isolate remaining repeated deep:L129 world_snapshot callers by concrete A-owned phase and prove read-only ownership/invalidation; coordinate ship/dock callsites with C, never edit C files.
