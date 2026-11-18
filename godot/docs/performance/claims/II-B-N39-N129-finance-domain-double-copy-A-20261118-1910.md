# Astra II-B — N129 finance domain double-copy
STATUS: IN_PROGRESS
OWNER: A
START: 2026-11-18 19:10 MSK
BASE HEAD: 40c821317e1fb4d23f5c08b74fd58e78c137a8b5
SOURCE: ASTRA_FIVE_SHIFTS_RU.md II-B bounded owned write sets / alias rollback / Schema oracle
TASK: Remove redundant full deep copies of facilities/populations in active N129 finance stage, preserve exact account roster, ledger and failure isolation.
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n129_finance_domain_owned.gd
EXPECTED CHECK: positive multi-wallet same-seed deep-copy oracle; negative missing roster, no-op, nested alias and rejected transfer; Schema/N9 parity. No Actions.
