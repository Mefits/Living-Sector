# PERF B — N9 paid fork: remove discarded 1024-shard allocation (20:09 MSK)

- Code SHA: `ef7b76d8f54299c4359ec1b5592be1a6a088d907`
- Targeted regression SHA: `c67ded8681d9aaa8c3a1ebdc6208b017cf81fe3d`
- Files: `godot/scripts/sim/economy/credit_ledger.gd`, `godot/tests/p2_perf_b_trusted_fork_allocation_negative_20261116.gd`
- Branch: `integration/perf-astra-5-workers-20261116` / draft PR #262

## Real hotpath, concrete change
N9 `_profile_inner_fork()` previously called `get_script().new()`, whose `_init()` allocated 1024 empty receipt dictionaries and a 1024-slot header. The next statement immediately replaced this header with `_receipt_partitions.duplicate()`. Thus every trusted fork (frequent in N39 transaction stages) paid for 1024 disposable shard allocations regardless of receipt count. Now `_init(trusted_fork=false)` initializes normally for fresh/restore instances, while `fork()` calls `new(true)` and immediately sets a detached parent header. No mutation or new public financial entrypoint; no changed receipt hash, commit semantics, insertion order, shard count, balances, N38 format, or save recovery.

## Regression / status
`p2_perf_b_trusted_fork_allocation_negative_20261116.gd`: 160 original paid receipts, fork exact snapshot and COW proof, child-only payment does not mutate parent, complete N38 v1 restore parity, healthy ordinary constructor/index. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN: no Godot execution in this connector-only iteration. No measured before/after TPS or N9 call-site cost; do not claim a speedup yet. This removes a source-proven constant per-fork allocation, but the late-tick 10x cause remains unproven.

## Next action
At the next shared bounded CI checkpoint, run this targeted negative test and compare `LS_PROFILE_LEDGER=1` fork call counts/cost with same seed at tick100/300/600/900, along with `LS_PROFILE_N9_APPEND=1` shard detach/snapshot counts. If N9 still grows with receipt count, target measured `_append_receipt` COW bucket copies; do not blindly increase partitions again. Coordinate any N39 call-site changes with A.
