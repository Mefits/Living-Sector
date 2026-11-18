# Astra II-B — N143 research paid shifts row ownership
STATUS: IN_PROGRESS
OWNER: A
START: 2026-11-18 21:10 Europe/Moscow
BASE_SHA: 7c70cc48428fe4e05e36b74fb03ef9d693378597
ASTRA: N39 L196 paid stage owned-write, rollback, alias isolation, full Schema/N9 oracle.
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n143_research_owned_rows.gd
PLAN: replace nine full-domain deep copies in live N143 paid research with shallow owned roots, detach only actual paid actors before mutation, preserve strict validation and atomic publication, negative late failure and deep-copy oracle.
TEST: NOT_RUN
