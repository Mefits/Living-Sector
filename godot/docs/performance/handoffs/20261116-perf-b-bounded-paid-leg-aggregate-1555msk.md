# PERF B 16.11 — bounded N9 paid-leg aggregate

Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262. No merges.

**CODE COMMIT:** `7adc9e5e7bfe8c341cde50ef78c52d61e54aa989`
**TEST COMMIT:** `5d0f8b841fe2956cfd3a5ab4398d95bcd42a86ed`

Files:
- `godot/scripts/sim/economy/credit_ledger.gd`: new read-only `paid_leg_totals_for_operations(operation_ids)`. Bounded exact operation ID index lookup; sums verified committed immutable legs without `snapshot()` or history scan. Rejects empty/missing/duplicate IDs, malformed legs, one-leg write-offs, unbalanced receipts, and i64 overflows. Returns detached per-account signed totals; does not mutate money/stock/cargo/World or authorize any operation.
- `godot/tests/p2_perf_b_paid_leg_aggregate_negative_20261116.gd`: two paid transfers, reversed IDs, no alias, duplicate/missing/empty, fork isolation, N9 snapshot restore, writeoff rejection.

**TEST EXECUTED: NOT RUN; CODE_UNVERIFIED.** GitHub connector writes succeeded. Godot 4.7.2 not executed. No throughput measurement, no integration with A/N39, no claimed speedup.

**NEXT:** B-owned targeted Godot script compile/test; coordinate with A to replace only proven full-history paid-leg scans using this read-only API, with exact World/N9/N38 checkpoint and replay comparison. Keep existing financial guards. Late-tick sim cost remains unresolved. Do not enable N38 vNext.
