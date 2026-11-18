# PERF B · N9 real snapshot cost split · 17.11.2026

CODE COMMIT: 384b4475296414dd5339e2e874a8606bd67b1a29
TEST COMMIT: 66b1aacd500e46e6e9dd7397cf2ff9adee8db81d
FILES: godot/scripts/sim/economy/credit_ledger.gd; godot/tests/p2_perf_b_n9_snapshot_cost_split_20261117.gd
STATUS: CODE_UNVERIFIED / TEST_ADDED_NOT_RUN; no runtime performance improvement claimed.

Existing LS_PROFILE_N9_APPEND=1 measures real paid-path append and full snapshot costs, but cannot distinguish O(R) ID map rebuild from O(R) deep copy of immutable receipts. The actual _snapshot_receipts() hotpath now accumulates snapshot_rebuild_calls, snapshot_rebuild_usec, snapshot_copy_usec without extra traversal or serialization. Disabled by default; N9 snapshots, N38 formats, balances, receipts and transaction rules unchanged. The negative test covers cached snapshots, append invalidation, detached fork and duplicate paid operation.

Next: capture actual N9 profile deltas on tick100/300/600/900 with existing bounded profiling, and correlate with receipt_count, N38 encoded bytes and paid tick phase time. If snapshot costs are insignificant, stop B micro-optimizations. This change is diagnostic and does not establish N9 as a cause of slowdown. Do not repeat 99ab25e9 / 1676db61.
