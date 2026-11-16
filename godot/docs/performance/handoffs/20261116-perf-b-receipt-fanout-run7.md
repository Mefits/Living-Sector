# PERF B · Paid receipt COW fanout, 16.11.2026 run 7

Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262. Frozen Rust 0.6.7 logic unchanged.

- Code: `64ab2afa104efd82a04c4bc2cca34aed27ca3ea9` — `godot/scripts/sim/economy/credit_ledger.gd`. Increased `RECEIPT_PARTITIONS` from 256 to 1024, maintaining power-of-two hashing and the original N38 v1 order/format. The actual `commit → _append_receipt` hotpath clones only its selected shard on every paid receipt; the fixed-width fork header becomes 4x larger, while the expected old rows copied per append at the same journal size become about 4x fewer assuming reasonably distributed IDs. This is a **trade-off, not a measured speedup**. No additional ledger authority or balances/cargo/contract changes.
- Existing oracle adjustment: `c52b2f575913ce236ab6c1ef628edbd1e3f15812` — `godot/tests/p2_perf_b_receipt_storage_profile_20261116.gd` uses the authoritative partition constant instead of 256.
- New negative test: `b1e161cc6beb3d551e28f06bba7475a877e2b013` — `godot/tests/p2_perf_b_receipt_fanout_20261116.gd`: 2048 real paid receipts, duplicate rejection, fork isolation, exact N38 v1 snapshot/restore, detached snapshot tamper, balances and index audit.

**TEST: NOT RUN / CODE_UNVERIFIED.** No Godot execution or same-seed early/late throughput measurements. The source-level O(R/partitions) clone mechanism is confirmed in `_append_receipt`; no claim that this dominates ships/dock/market time or that 1024 is optimal. Default authoritative N9 remains a single ledger; existing old N38 saves restore into the same insertion order.

**Next concrete step:** B-owned bounded same-seed `LS_PROFILE_N9_APPEND=1` checkpoint at 100/300/600/900 paid ticks, compare `append_usec/append_calls`, `append_old_shard_rows`, `snapshot_usec` and total paid tick ms against the 256-partition baseline; run the two targeted tests and N38 restart/parity before accepting the fanout increase. If extra fixed fork cost dominates or actual N9 share is insignificant, revert this experiment. Do not extend CI beyond 12 min or introduce N38 vNext.
