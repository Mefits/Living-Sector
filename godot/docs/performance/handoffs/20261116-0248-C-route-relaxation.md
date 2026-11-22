# PERF C — route relaxation allocation, 2026-11-16 02:48 MSK

Branch: `integration/perf-astra-5-workers-20261116`; draft PR #262.

Code commit: `a2dfffa20256ed93df5d41b6e65c91f50522746b`.
Test commits: `00f64fe08b9be0c7752045678b16f2ae096485ad`, `260060a2883be9494d9f3390cb77920866e3ade3`.

Files:
- `godot/scripts/sim/route_graph.gd`: skip building the candidate lexicographic path string on strictly worse, non-approximately-equal relaxations. Keep original distance, approximate-tie comparison and previous-node update; do not alter directed graph, cache, travel, cargo, fuel or contract logic.
- `godot/tests/p2_perf_c_route_relaxation_oracle.gd`: 24-node dense directed graph, 576 start/destination combinations, cached second pass, unknown nodes, near-equal floating-point ties. Compare against independently copied pre-change Dijkstra oracle using detached outgoing edges.

Validation: source-level inspection only. **CODE_UNVERIFIED; TEST_ADDED_NOT_RUN**. No Godot execution or benchmark, no FPS/TPS improvement claim. No GitHub Actions run. Static check: preload path `res://scripts/sim/route_graph.gd` exists, oracle uses existing public `has_location`, `outgoing`, `load_worlds`, `shortest_path` signatures.

Why: dense route graphs perform many dominated relaxations; avoid constructing a string for each without changing path choice. This is a bounded local optimization, not a new routing backend.

Next: execute `p2_perf_c_route_relaxation_oracle.gd` and existing `p2_perf_c_route_fifo_oracle.gd` in Godot 4.7.2; then profile route graph in a real paid-contract scenario and compare cached vs uncached decisions, N38 restart, fuel/cargo/receipt replay before accepting a measurable speedup.
