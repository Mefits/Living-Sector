# Astra II-B — N152 refund wallet row ownership
STATUS: IN_PROGRESS
OWNER: PERF A
START: 2026-11-19 03:13 MSK
BASE HEAD: 063b3658b2a868ba2282927aa768b6e09d7ad122
SOURCE: ASTRA_FIVE_SHIFTS_RU.md / II-B bounded owned write sets, N39 L129/L196; live apply_native_n152_contract_lifecycle.
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n152_refund_owned_rows.gd; this claim.
PLAN: replace deep cloning whole facilities/populations during paid refund with root copy and first-write per payer row, preserve escrow and treasury scalar semantics, full Schema + N9 oracle and rollback. Regression with positive multi-refund, repeated payer, negative missing payer and nested alias.
TEST: NOT_RUN
