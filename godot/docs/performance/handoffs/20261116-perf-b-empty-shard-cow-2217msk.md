# PERF B — N9 first append into empty shard (16.11.2026, 22:17 MSK)

- Code commit: `708d229db806deec112e343a5fc4bc9ec08d3ff6`
- Test commit: `591fca5d65c252c3a689a3661c375f43530dda6b`
- Files: `godot/scripts/sim/economy/credit_ledger.gd`, `godot/tests/p2_perf_b_empty_shard_append_cow_20261116.gd`
- Result: `_append_receipt()` skips shallow-copying a dictionary when the selected shard has zero rows. Populated shards retain the existing copy-on-write path; receipt order, balances, operation ID and N38 v1 serialization are unchanged.
- Negative regression: first append in fork, parent/sibling isolation, replay rejection, exact N38 restore, index audit, detached snapshot mutation.
- Status: **CODE_UNVERIFIED / TEST_ADDED_NOT_RUN**. No Godot runtime execution or same-seed paid-tick speed measurement. The expected saving is limited to first inserts into empty buckets; **no evidence this explains late-tick slowdown**. Do not report speedup.
- Next: use existing N9 append/fork profiling and real tick100/300/600/900 data to determine whether populated-shard COW dominates paid tick; compare same-seed with/without this change and exact N9/N38 parity. If insignificant, stop optimizing N9 append and report negative result rather than further speculative shard tuning.
