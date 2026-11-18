# Astra II-B — N143 research paid shifts row ownership
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: A
START: 2026-11-18 21:10 Europe/Moscow
BASE_SHA: 7c70cc48428fe4e05e36b74fb03ef9d693378597
CLAIM_SHA: 9f71a01b59bafbf17d1d871035a6f6b8e538f357
ASTRA: N39 L196 paid stage owned-write, rollback, alias isolation, full Schema/N9 oracle.
CODE_SHA: 9e564cdc98246f216df497c99d1b567165e116b4
TEST_SHA: 7d6bcd778468b161e40825dc47b55c45cfac518b
FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n143_research_owned_rows.gd
CHANGE: N143 apply_native_research_phase no longer deep-copies nine entire mutable registries before each research phase. It shallow-owns nine registry roots; only market/facility/household rows that actually receive a verified paid shift are deep-detached, once per actor. Repeated paid shifts see the previous committed staged row. Research director, technology, receipt and player policy entries are replaced by detached values; treasury balances are scalar. Validation, N9 fork/receipt verification, complete Schema.accounts and staged publication are unchanged.
REGRESSION: added oracle fixture comparing full-domain deep-copy vs row ownership, repeated payments, duplicate late receipt, unfunded negative, no-op, and nested alias isolation. This fixture models paid write ownership; it does not directly execute the production N143 phase or prove N38 parity.
TEST: NOT_RUN
CODE: UNVERIFIED
PERFORMANCE: NOT_MEASURED
RISK: production N143 must be exercised with source-intent fixtures and exact same-seed full World/N9/N38 oracle before acceptance. Full Schema may dominate cost; benchmark needed.
NEXT ASTRA II-B: examine remaining deep:L129 world_snapshot callsites, especially N39-owned paid phase boundary reads, and remove repeated snapshots only with proof of no intervening World mutation; add direct production parity/negative tests.
