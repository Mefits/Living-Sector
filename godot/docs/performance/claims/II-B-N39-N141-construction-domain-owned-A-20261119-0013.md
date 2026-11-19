# Astra II-B — N39/N141 construction owned domains
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: A
START: 2026-11-19 00:13 MSK
BASE SHA: 2bd156ab5920a55144436f8aa31128a88efef71c
ASTRA: II-B bounded owned write sets / rollback and alias isolation; reduce N39 paid tick deep-copy cost.

CODE SHA: e7471ee171d39941b72c3c196111da6680f18ca9
TEST SHA: d7c16651ce79cd15d11e08ecb9cafd6a6ea1e350
FILES:
- godot/scripts/sim/phase1/n39_native_world_production.gd
- godot/tests/p2_perf_a_n141_construction_domain_owned.gd

REAL PATH: apply_native_construction_labor() now stages six construction-related domains shallowly for ordinary N141 paid shifts; the existing owned household detach remains, site updates replace detached site rows, and receipts/contracts/facilities are added or removed at owned registry roots. Colony B3 retains deep copy of all seven domains. Full _measured_schema_validate and N9 account/total checks remain unchanged. No cadence, ledger, or balances modified.

TEST: NOT_RUN / CODE_UNVERIFIED / PERFORMANCE_NOT_MEASURED.
TEST COVERAGE: invokes production _n141_owned_construction_domains; old deep-copy oracle; repeated paid changes; nested alias isolation; discarded late stage; colony B3 fallback. Full runtime N141 and N38 same-seed still unverified.

NEXT ASTRA II-B: investigate remaining deep:L129 snapshots at concrete N39 callers, especially repeated paid phases; preserve published-stage rollback boundaries, compare full Schema/N9/N38 same-seed on Windows.
