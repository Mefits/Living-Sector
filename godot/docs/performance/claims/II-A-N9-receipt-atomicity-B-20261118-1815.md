# Astra II-A — N9 immutable paid receipt publication
STATUS: IN_PROGRESS
OWNER: B
START: 2026-11-18 18:15 MSK
BASE_SHA: f79a75461e73e98198eb317ab9fc577dbfaf7339
ASTRA: II-A, remaining receipt immutability / paid transaction overlay / idempotency
INTENDED_FILES: godot/scripts/sim/economy/credit_ledger.gd; godot/tests/p2_perf_b_receipt_atomicity.gd
EXPECTED: positive and negative regression for external mutation, failed operations, fork, N38 restore, exact snapshots; no Actions.
RISK: N9 money/receipt exact parity; no default experimental shard reuse.
