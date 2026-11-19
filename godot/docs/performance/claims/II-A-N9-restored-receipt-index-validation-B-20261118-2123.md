# Astra II-A / B — N9 restore receipt index validation
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: B
TIME: 2026-11-18 21:23 MSK
BASE: integration/perf-astra-5-workers-20261116; ledger blob ae371910627d627c279fe5c1c7a9bf3f08dcda5e
ASTRA: II-A N9 receipt/provenance/index, N38 immutable restore and negative oracle
FILES: godot/scripts/sim/economy/credit_ledger.gd; godot/tests/p2_perf_b_restore_receipt_validation.gd
GOAL: validate untrusted receipt rows and order atomically before publishing restored N9; reject forged malformed and duplicate entries while preserving legacy valid rows and exact order.
TEST: positive N38 restore, negative malformed receipts, atomic rollback and fork lineage.

CODE SHA: 8702a954687e4fd2d445858cec25ef59992bf5f2
TEST SHA: 24539f7771f2ed889384aa8097e249339b65a411
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED
IMPLEMENTED: N9 restore validates untrusted receipt legs, optional tick/kind and known money metadata before publishing wallet/index. Rejects malformed nested rows, noninteger credit legs, empty accounts, i64 minimum, invalid tick, malformed metadata. Existing single-leg historical writeoffs remain legal. Added 70-receipt N38 positive, nine malformed negatives, atomic failure, restored fork isolation oracle.
RISK: compatibility of unusually malformed legacy save rows; needs actual Godot parser and old-v1 fixture verification. No benchmark claim.
NEXT ASTRA II-A: measure actual N9 paid receipt detach and snapshot deep-copy at ticks 100/300/600/900; optimize only measured hotpath with exact old/new history and balance parity.
