# Astra II-A / B — N9 restore receipt index validation
STATUS: IN_PROGRESS
OWNER: B
TIME: 2026-11-18 21:23 MSK
BASE: integration/perf-astra-5-workers-20261116; ledger blob ae371910627d627c279fe5c1c7a9bf3f08dcda5e
ASTRA: II-A N9 receipt/provenance/index, N38 immutable restore and negative oracle
FILES: godot/scripts/sim/economy/credit_ledger.gd; godot/tests/p2_perf_b_restore_receipt_validation.gd
GOAL: validate untrusted receipt rows and order atomically before publishing restored N9; reject forged malformed and duplicate entries while preserving legacy valid rows and exact order.
TEST: positive N38 restore, negative malformed receipts, atomic rollback and fork lineage.
