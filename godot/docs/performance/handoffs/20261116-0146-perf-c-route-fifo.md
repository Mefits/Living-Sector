# PERF C handoff — 2026-11-16 01:46 MSK

CODE commits: `2b00fbe3d90ce3cc75bafdf6eaef8571aa9ac4a2`, `44231b88df0a5133e04f3623140fa8f8f4125f40`.
Branch: `integration/perf-astra-5-workers-20261116`; PR #262. No merge or CI.

Files:
- `godot/scripts/sim/route_graph.gd`: replace full 4096-entry cache flush with bounded FIFO eviction of exactly one pair, compact queue periodically. Preserve directed Dijkstra, tie-break, negative caching, deep-copy isolation and successful-load invalidation.
- `godot/tests/p2_perf_c_route_fifo_oracle.gd`: exercise >4096 unique queries, negative paths, cached vs uncached results, mutation isolation, reload invalidation.

Tests: NOT RUN (Godot runtime unavailable here). CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. Static review only; no measured speedup. Expected benefit: avoid cache-wide cold misses on saturation; no claim of measured FPS/TPS benefit. Full N38 restart, paid contracts, fuel/cargo and deterministic replay remain unverified.

Next: execute targeted test in Godot 4.7.2; compare cache hit/miss profile on actual N153 routes and run paid-world checkpoint/N38 restart before accepting. If little measurable benefit, revert this experiment.
