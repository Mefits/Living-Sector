# PERF B — bounded N9 provenance batch (2026-11-16 05:58 MSK)

- Branch: `integration/perf-astra-5-workers-20261116`; draft PR #262.
- Code SHA: `c9527308a6a24b06b7dd756e6d391503e1e885bb`.
- Test SHA: `f2182e94f8bc3bae14ec0893569d30b565c99d98`.
- Files: `godot/scripts/sim/economy/credit_ledger.gd`; `godot/tests/p2_perf_b_receipt_batch_provenance_check.gd`.
- Added `receipts_for_operations(operation_ids: Array)`: bounded O(k) shard lookup for caller-supplied operation IDs; returns detached immutable-by-ownership receipt copies. Rejects duplicate/empty/non-string/missing IDs atomically, without copying unrelated historical N9 receipts or modifying ledger.
- Targeted negative regression: two paid receipts, requested order, nested mutable-alias attempt, duplicate/unknown/non-string/empty IDs, fork isolation, restore, unchanged balances and receipt count.
- Test execution: **NOT RUN** (Godot runtime not invoked). Code status: **CODE_UNVERIFIED / TEST_ADDED_NOT_RUN**. Source-level checked against current N9 method signatures and existing `p2_perf_b_receipt_lookup_check.gd`. No measured performance benefit; theoretical lookup work scales with requested IDs, not historical journal size.
- No change to World/N39, money, source cadence, N38 save format, 16 MiB limit or backup rotation.
- Next: have A identify an exact N39 provenance proof site that currently takes a full `Ledger.snapshot()` solely to read known operation IDs; agree contract and replace only that call in A-owned code. Execute this regression and full N38/checkpoint negative tests before integration. Measure same-seed old/new receipt lookup time.
