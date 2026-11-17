# PERF B — N9 receipt cache invalidation (17.11.2026)
Code: 3a8ea3dbdac9b28e568f22390087291cb9b35507 (superseded by correction ae0becca2fc16369068d8dc2d69493963b97a82f).
Test: 5f56f5e6e58cf7c1cdbe1460f9f8b67d451e78ed.

Files: godot/scripts/sim/economy/credit_ledger.gd; godot/tests/p2_perf_b_receipt_cache_single_invalidation_20261117.gd.

Actual hotpath: N9 _append_receipt() previously allocated a fresh empty Dictionary and invalidated _flat_cache_count on *every* paid receipt, even if no full snapshot had rebuilt the cache since the previous payment. Now the full cache is released once on its first invalidation, and subsequent appends keep the already-empty map. On next snapshot, the existing rebuild path runs unchanged. This avoids redundant allocations in repeated paid appends without retaining an old full-history cache. No N39/N158/N152/WeakRef edits; no save format or payment semantics changed.

Test covers first cache materialization, first and repeated invalidations, snapshot rebuild, fork isolation, duplicate rejection, exact N9 restore and mutable alias negative. CODE_UNVERIFIED; TEST_ADDED_NOT_RUN. No Godot runtime run; no CPU/paid tick measurement or performance gain claimed. The earlier PASS #43972442164 predates this patch.

Next: use E's bounded same-seed paid-tick profiler to establish actual N9 append/snapshot calls and CPU time at early and late windows, with receipt count and N38 encoded bytes. If N9 share is negligible, stop N9 micro-optimizations. Do not enable experimental shard reuse or N38 vNext without parity/restart proof.
