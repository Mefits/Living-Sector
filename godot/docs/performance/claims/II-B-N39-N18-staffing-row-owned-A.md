# II-B · N39 N18 staffing owned rows
STATUS: IN_PROGRESS
OWNER: A
DATE: 2026-11-18 11:05 MSK
BASE SHA: 7685bce60f65d1d1ad3ffe1e268078acd305c3be
ASTRA: II-B N39 owned-write stages / Schema-oracle / rollback and alias isolation; frequent run_tick N18 staffing following L196 lifecycle.
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n18_staffing_row_owned_stage.gd.
EXPECTED: preserve full Schema and N9 accounts oracle, detach only changed facility rows, reject missing/malformed assignments atomically; positive and negative full-copy oracle.
TEST: NOT_RUN
