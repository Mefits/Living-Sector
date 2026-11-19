# Astra II-B — N152 refund wallet row ownership
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: PERF A
START: 2026-11-19 03:13 MSK
BASE HEAD: 063b3658b2a868ba2282927aa768b6e09d7ad122
SOURCE: ASTRA_FIVE_SHIFTS_RU.md / II-B bounded owned write sets, N39 L129/L196; live apply_native_n152_contract_lifecycle.
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n152_refund_owned_rows.gd; this claim.
PLAN: replace deep cloning whole facilities/populations during paid refund with root copy and first-write per payer row, preserve escrow and treasury scalar semantics, full Schema + N9 oracle and rollback. Regression with positive multi-refund, repeated payer, negative missing payer and nested alias.
CODE SHA: af2d29272dafe792081aafd888b5bad1001b18ad
TEST SHA: 8a89c1df513ba25e646aaa1aac4c95a687fafde1
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED
CHANGED: live apply_native_n152_contract_lifecycle refund publication; _n152_owned_refund_wallet_stage; _n152_detach_refund_wallet_row. Full Schema oracle, N9 refund receipt/balance checks, restore and atomic publication unchanged. Multi-refund same payer copies once. Negative missing payer, late malformed stage, alias isolation modeled in p2_perf_a_n152_refund_owned_rows.gd. No Godot or Actions run.
NEXT: Astra II-B N39 remaining deep:L129/L196 in live paid stages, prioritize construction escrow or population migration with strict full Schema/rollback oracle.
