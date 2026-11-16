# PERF B · receipt lookup · 2026-11-16 03:50 MSK

Branch: `integration/perf-astra-5-workers-20261116`; PR #262. No merge.

## Code
- `ae866f515eddcbc60b988eb9c089d0fc9f3e7873` — `godot/scripts/sim/economy/credit_ledger.gd`: `receipt_copy(operation_id)`, direct shard lookup and detached deep copy. No journal scan/snapshot, no new authority or changes to payment, restore, order, balances or N38 schema.
- `4bd3255c5e1cd1f8ea537e91eed57cfef1cb7252` — `godot/tests/p2_perf_b_receipt_lookup_check.gd`: receipt equality, nested mutable-alias negative, unknown ID, duplicate payment rejection, fork isolation, old receipt retention, restored provenance and rejected tamper with rollback.

## Verification
CODE_UNVERIFIED / TEST_ADDED_NOT_RUN: no Godot runtime executed in this iteration. Source-level checks: `Ledger.new()`, `import_accounts`, `transfer`, `fork`, `snapshot`, `restore`, `balance`, `has_receipt` and `receipt_copy` match current script signatures. The test uses only existing Ledger and no new preload dependencies. No performance benchmark; O(1) hash shard lookup avoids materializing complete history for a single receipt, while copying the returned receipt still costs O(receipt size).

## Next
Run `res://tests/p2_perf_b_receipt_lookup_check.gd` in a bounded Godot checkpoint. Ask A to replace a *specific* full `ledger.snapshot().receipts[id]` provenance read with `receipt_copy(id)` only after full World/N38 replay comparison; do not touch N39 from B. Measure N38 encoded save bytes on 420/900 snapshots before considering segmented vNext.
