# PERF B — private receipt order chunk ownership (17.11.2026)

CODE `de5298fc1135f8d5d4bbf9d453329c0d61ce32f0`; TEST `513b6de35a938347f2d17523786ec29ac9a4b143`.

Files: `godot/scripts/sim/economy/credit_ledger.gd`, `godot/tests/p2_perf_b_order_chunk_private_fork_negative_20261117.gd`.

In real `_append_receipt` the last order chunk was duplicated for each append, up to 63 prior String IDs, even when the ledger already privately owned the chunk. The existing experimental `LS_N9_PRIVATE_SHARD_REUSE=1` now also reuses the private last order chunk; both parent and child lose ownership at `fork()`. Newly allocated chunks are private. Default path remains unchanged. No N39/N158 edits, no new archive format, no balance or receipt semantics intended.

Negative regression compares opt-in and baseline over 151 operation IDs crossing 64-item chunk boundaries and fork divergence, N9 index audit, restore and duplicate operation rejection. TEST NOT RUN / CODE UNVERIFIED: Godot runtime not executed. No measured CPU improvement or evidence that this path dominates late ticks. Existing #43972442164 PASS predates this change.

NEXT: targeted parser + test in next bounded combined checkpoint, then opt-in same-seed append calls/usec and order-chunk costs at early/late windows. If insignificant, leave disabled and prioritize measured N38 or retention hotpath. Do not duplicate 99ab25e9 or 1676db61.
