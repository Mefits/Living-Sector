# PERF B — fail-closed N9 receipt partition audit (16.11.2026 11:30 MSK)

Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262.

- CODE COMMIT: `9d920e47910f7d9e923b968fdc589b600b7271f5`
- TEST COMMIT: `2fc0b4ea2e14c78e953a380809c5847113ea4cb2`
- FILES: `godot/scripts/sim/economy/credit_ledger.gd`; `godot/tests/p2_perf_b_receipt_index_structure_negative_20261116.gd`
- TEST EXECUTED: NOT RUN; CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No Godot runtime, CI or FPS measurement claimed.

WHY: the diagnostic `audit_receipt_index()` previously indexed the private shard array without checking its length or element types. A corrupted in-memory partition header could cause an out-of-bounds/type failure instead of a deterministic false verdict. New preflight rejects missing/extra partitions and non-Dictionary shards, without repairing or changing the authoritative ledger.

Targeted regression constructs a paid receipt, forks and corrupts only test-local private headers, verifies fail-closed rejection and checks the original snapshot and index remain unchanged. No production payment, N38 format, source cadence or World changes. This is correctness hardening, **not a measured speedup**.

NEXT: run `godot --headless --path godot --script res://tests/p2_perf_b_receipt_index_structure_negative_20261116.gd` on the agreed checkpoint, then N9/N38 restart and existing receipt-index tests. Compare with complete receipts and balances before enabling any N39 bounded provenance integration.
