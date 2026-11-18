# II-B · N39 N18 staffing owned rows
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: A
DATE: 2026-11-18 11:05 MSK
BASE SHA: 7685bce60f65d1d1ad3ffe1e268078acd305c3be
ASTRA: II-B N39 owned-write stages / Schema-oracle / rollback and alias isolation; run_tick N18 staffing after L196 lifecycle.

CODE SHA: b337191f4e44957e4a978aa3ece8e7bc0a324757
TEST SHA: a65c6a224ff121893a95943ae6bd8cb4c9f9062a
FILES:
- godot/scripts/sim/phase1/n39_native_world_production.gd
- godot/tests/p2_perf_a_n18_staffing_row_owned_stage.gd

FIX: Validate the entire N18 assignment map (exact keys/count and integer values) before staging; detach World root and facilities registry, deep-copy only rows whose assigned_workers change, and preserve the full Schema.validate and N9 accounts oracle before atomic publication. Unchanged rows remain shared read-only; changed rows are recursively detached. Existing N18 proposal/cadence and money semantics unchanged.
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED.
REGRESSIONS: full deep-copy equality including legacy missing assigned_workers; nested reserve/dock alias isolation on changed rows; rejection of missing/extra/malformed assignments; negative shallow alias demonstration.
NEXT: II-B N39 L196 lifecycle facility row ownership: inspect ServiceRestock/Payroll mutation sets and prove exact alias isolation before narrowing full facilities duplicate; then same-seed N38 and full Schema oracle on actual paid repair/restock.
