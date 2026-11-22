# PERF E — bounded phase p95, 17.11.2026

PR #262, branch `integration/perf-astra-5-workers-20261116`.

CODE COMMIT: `b5bb811257c7325c3d673a5da341f9e1e40b5aa7`
TEST COMMIT: `590c25b2ec31abe3f18f5dc13d46489f62172e71`

FILES:
- `godot/scripts/sim/phase2/n158_worker_request_metrics.gd`: existing `phase_window` now returns nearest-rank p95 and maximum for each of ships/dock_queue/markets/factions from exactly 100 sequential paid ticks; retains totals/averages. Only bounded scalar arrays, no World alias.
- `godot/tests/p2_perf_e_phase_p95_boundary.gd`: outlier threshold (six vs five), zero cost, aggregate, and duplicate tick rejection.

TEST EXECUTED: NOT RUN; CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No Godot runtime verification, no new CPU/FPS/TPS claim. This is elapsed wall timing, not per-thread CPU time; the adapter does not itself connect to actual per-tick phase timings.

NEXT: integrate authoritative per-paid-tick phase samples at existing N158 instrumentation boundary (no duplicate worker/UI), then bounded 100/300/600/900 same-seed profile and exact N38/BT/RNG parity against full-read oracle. Preserve 99ab25e9 and 1676db61. Do not run 2600-tick CI.
