# PERF B — N9 private shard reuse (17.11.2026, 09:00 MSK)

CODE COMMIT: f7a2e0e533246dcff7cff9a8cf8d6607ccdc9747
TEST COMMIT: aad88e6067cd4bc212f7abc0fc2ae1b711b3958e

Files: godot/scripts/sim/economy/credit_ledger.gd; godot/tests/p2_perf_b_n9_private_shard_reuse_20261117.gd.

Real hotpath: N9 _append_receipt() currently shallow-copies an entire occupied hash shard on every paid receipt, including multiple appends in the same authoritative fork. Added an **OFF-by-default** LS_N9_PRIVATE_SHARD_REUSE=1 experiment: a shard detached by this ledger may be modified again without another copy until the next fork. Fork invalidates the parent's ownership and starts the child with no owned shards; restore clears ownership. No changes to receipt format, balances, N38, WeakRef, N152, or N39.

Targeted negative test: two paid appends to same shard, parent/sibling isolation, further fork then independent paid appends, duplicate operation rejection, detached snapshot mutation, N38 v1 restore and branch-specific receipts.

STATUS: CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No Godot runtime executed; no speedup measured. The default production path is unchanged. This is a candidate only: enable after a targeted test, parity and same-seed paid tick profiling show material old_shard_rows and append_usec. The prior CI #43972442164 does NOT cover these commits.

NEXT: run this targeted test and late/early LS_PROFILE_N9_APPEND=1 measurements; compare calls, append_usec, old_shard_rows and paid tick p95. If N9 remains insignificant, leave flag off and report negative finding. Do not repeat 99ab25e9/1676db61 or launch a long CI per commit.
