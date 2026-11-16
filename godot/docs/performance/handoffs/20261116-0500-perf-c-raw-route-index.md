# PERF C handoff — 2026-11-16 05:00 MSK

- Branch: `integration/perf-astra-5-workers-20261116`; PR #262.
- CODE COMMIT: `f97783fa359fdb34363dc8c477b931f2c9b5fe12`.
- TEST COMMIT: `95f66caf24257879a0c6e1d92ef5e0bd5f90a3a6`.
- Files: `godot/scripts/sim/route_graph.gd`, `godot/tests/p2_perf_c_raw_route_index_oracle.gd`.
- Change: raw directed N4 loading now uses per-origin destination membership index instead of O(outdegree) duplicate scan for every edge. Native-seeded upsert path and all shortest-path/contract/fuel/cargo behavior unchanged. Raw duplicates still fail, including duplicates across worlds; failed load leaves graph/cache untouched.
- Regression: dense 40-node directed graph (1560 arcs), cached-vs-uncached shortest path, cross-world duplicate, reverse-edge distinction, duplicate rollback and cache persistence.
- TEST EXECUTED: NOT RUN; CODE_UNVERIFIED. Godot runtime unavailable in this run. Static review only; no measured TPS/FPS gain, no N38 restart evidence. No Actions launched.
- Next: run raw-route oracle together with FIFO/dense route oracles, then profile load_worlds on large valid route graphs. Follow with real N153 paid-contract ship selection profiling before changing any ship/contract index.
