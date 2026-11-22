# PERF B · 17.11 · N9 snapshot receipt ID conversion

CODE COMMIT: ef2ba20c385e363a7f161115c911643663299541
FILES: godot/scripts/sim/economy/credit_ledger.gd
Change: _snapshot_receipts() reads already-validated String IDs directly instead of str(id) for every receipt during cache rebuild. This is a bounded, semantics-preserving per-receipt reduction in the real snapshot hotpath; no new index, no N9 fork/WeakRef/N152 changes.
Targeted negative test: godot/tests/p2_perf_b_receipt_order_string_snapshot_20261117.gd (130 receipts, chunk boundary, fork isolation, exact snapshot/restore, mutable alias and duplicate operation).
TEST EXECUTED: NOT RUN; CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. Benefit NOT MEASURED; no claimed reduction in late-tick CPU. Existing CI #43972442164 predates this change and does not verify it.
NEXT: Measure actual N9 snapshot calls/usec and N38 encoded bytes at tick100/300/600/900 with same seed, compare before/after, and stop N9 work if contribution is negligible. No 900/2600 soak or new CI started.
