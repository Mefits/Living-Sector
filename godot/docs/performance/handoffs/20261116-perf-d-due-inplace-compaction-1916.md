# PERF D — live due extraction compaction (2026-11-16)
- Code commit: 91a30a77c7c420f0f317e2b2107f66fc106ff770
- Test commit: f3e3a4b26e66673c5df07d7be17d213afdc5d879
- Files: godot/scripts/sim/event_queue.gd; godot/tests/p2_perf_d_due_compaction_oracle_20261116.gd
- Replaced take_due's second surviving-event array and full _positions.clear/rebuild with in-place stable compaction and updates only for moved survivors. _pending remains sole event store; canonical result sorting unchanged; cancel and restore unchanged.
- Existing due-count empty-boundary fast path remains. This improves allocations and redundant index rebuilding on populated boundaries; scanning for matches remains O(E), so this is NOT a demonstrated fix for late-tick degradation.
- TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No Godot runtime or same-seed measurements in this run. No CI started.
- Negative oracle covers cancellation of first/last, unknown IDs, repeated extraction, deterministic due ordering, restore and corrupt restore atomicity.
- Next: run targeted test, compare before/after same-seed early/late phase cost and p95 with counts of pending/due events; check exact N38 restart and N9/N39/BT/RNG parity before accepting. If event queue is negligible relative to market/head, prioritize measured N150/admin path.
