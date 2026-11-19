# Astra II-B — N39 N104 accept owned rows
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: A
START: 2026-11-19 08:12 MSK
BASE BLOB SHA: d13503a058b1b3db72ab694eafdd91f38107de5b
BACKLOG: II-B bounded owned write sets, rollback and Schema oracle; N39 L196 paid stages.
SCOPE: apply_native N104 contract acceptance: escrow/faction/facility/ship detached write-set instead of four deep domain clones.
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n104_accept_owned_rows.gd.
CHECK: old deep-copy oracle equivalence, nested alias, missing row, negative rollback; full Schema and N9 preserved. TEST_NOT_RUN pending Godot.

CODE SHA: 97e4434de3449c672b1fde14250b1ddc9b3e144d
TEST SHA: 7ceb3af311feaf8ab05336fbd878b368c797fd51
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED
RESULT: apply_native N104 acceptance now stages escrow/faction roots and only the changed ship and optional payer facility row. ContractBoard.snapshot, full Schema validation, N9 account oracle and atomic World/Ledger commit retained. No mutation of unrelated rows. Negative oracle covers missing escrow/ship/payer, malformed rows, failed-stage rollback and nested mutable aliases. The targeted test exercises stage helper, not full production accept.
NEXT ASTRA II-B: inspect remaining N39 paid production/ship service domain copies and consolidate proven owned-write callsites with same-seed full Schema/N9/N38 acceptance.
