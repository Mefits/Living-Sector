# PERF E handoff — 2026-11-17 worker request p95 attribution

Branch: `integration/perf-astra-5-workers-20261116` / draft PR #262.

Code commit: `abef086d50a82efa1ad3328f5aeb3b8b9d75e771`.
Test commit: `942581dcc142c206f99e93562c912a06f3e9bef6`.

Changed `godot/scripts/sim/phase2/n158_worker_request_metrics.gd`: existing bounded 100-paid-tick window now independently reports p95 for projection and complete worker request, not only source advance. Each metric uses its own sorted bounded scalar series; no World copies or mutable aliases. No worker/UI/clock/AI/economy behavior changes.

Added `godot/tests/p2_perf_e_worker_projection_p95_20261117.gd`: fixed 100-tick fixture with late projection outliers, nearest-rank p95 assertions, averages, and invalid repeated tick negative case.

TEST RUN: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No Godot runtime executed, no new FPS/TPS claim. Previous CI #43972442164 predates these changes.

Next: run this targeted regression in a coordinated short checkpoint, then capture real 100/300/600/900 paid tick samples and N38/BT/RNG parity. Distinguish elapsed wall time from CPU time and avoid a 2600-tick soak.
