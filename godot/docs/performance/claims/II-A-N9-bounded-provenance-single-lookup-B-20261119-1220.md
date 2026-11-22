# Astra II-A — B bounded provenance single-lookup
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: B
START: 2026-11-19 12:20 MSK
BASE_SHA: 689cb363f8b4f2ef877ed1b5d85c1d1cc780767b
BACKLOG: II-A N9 append-only + stage overlays + invariant transaction + provenance
CODE_SHA: 9990fac4707e6b8ba5e56c895ce0240ec5db16ab
TEST_SHA: 2d6895d0003d958759124b2234947b9704a58cd3
FILES: godot/scripts/sim/economy/credit_ledger.gd; godot/tests/p2_perf_b_n9_bounded_provenance_lookup.gd
CHANGE: Replaced redundant _has_receipt_id + _receipt_at double shard lookup with one _receipt_at lookup and fail-closed empty-record check in receipt_copy, receipts_for_operations, verify_operation_provenance, verify_exact_operation_receipts, paid_leg_totals_for_operations. No full-history snapshot, no N38 format change, no authoritative write-path change.
REGRESSION: snapshot oracle for exact receipt rows and paid account deltas; absent, duplicate, empty, truncated proofs; detached returned legs; fork isolation; N38 restore/index audit.
TEST: NOT_RUN
CODE: UNVERIFIED
PERFORMANCE: NOT_MEASURED; expected reduced bounded read hash probes, no claim of paid-tick speedup.
RISK: Requires Godot 4.7.2 parser and oracle execution, same-seed N9/N38 parity before performance claim.
NEXT: Astra III N38 segmented archive / save bytes growth: characterize encoded checkpoint size versus receipt count and design backward-compatible bounded archive path without changing v1 by default.
