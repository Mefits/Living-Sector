# PERF B · Exact bounded N9 receipt provenance (16.11.2026, 13:24 MSK)

Branch: `integration/perf-astra-5-workers-20261116`; draft PR #262. No changes to N39/main/worker/ship modules.

## Code commits
- `0655f85285fc45fb95aa4abf9483d4dc5e9a0754` — `godot/scripts/sim/economy/credit_ledger.gd`: `verify_exact_operation_receipts(expected_rows)`, a bounded private-shard proof of full immutable receipt fields. Rejects empty, duplicate, missing, omitted and forged rows; no snapshot, mutation or second ledger.
- `a55bae2d9b0436c67d6917ceaf2bab055c45093d` — `godot/tests/p2_perf_b_exact_receipt_provenance_check.gd`: targeted negative test, mutation isolation, fork, balances, audit.

## Status
CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No local Godot execution claimed, no speedup measured. The new method is opt-in/read-only and does not change current paid transaction or N38 save paths. Existing `verify_operation_provenance` retains its subset-matching behavior; exact method is a stricter alternative when callers have complete expected receipts. Source syntax and preload path checked against current GitHub blobs.

## Next
Run `godot --headless --path godot --script res://tests/p2_perf_b_exact_receipt_provenance_check.gd` at the next bounded shared checkpoint. Then inspect an A-owned N39 proof callsite with owner A and agree whether full receipts are available for opt-in replacement; do not alter N39 without coordination. Follow with N38 encoded-size budget growth regression against the existing `encoded_checkpoint_budget` and 16 MiB limit.
