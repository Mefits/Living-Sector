# PERF E — 17.11.2026, upper-tail acceptance guard

Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262. No merge.

## CODE_COMMITTED
- `a6a4b5cd745ad8e9f340ca323b3c9377097ff3c7`: `godot/scripts/sim/phase2/n158_worker_request_metrics.gd`. Reject mathematically impossible phase distribution when total exceeds `95*p95+5*max` for exact 100 samples and nearest-rank p95 index 94. This supplements existing lower bound `max+5*p95`.
- `a984ac03c9b78201dc180affc28463e612e1ff40`: `godot/tests/p2_perf_e_phase_p95_upper_tail_20261117.gd`. Positive baseline and negative forged total=1500, p95=10, max=100; upper bound=1450.

TEST_RUN: NOT RUN; CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No Godot runtime execution, CI not triggered. No measured FPS/TPS or tick acceleration. This is an acceptance integrity fix only. No worker/UI changes, no balance/AI/World/N9/N38 modifications, no rework of 99ab25e9 or 1676db61.

Next: run targeted Godot test once alongside a bounded paid-tick profile to 900 (8–12 min budget), with authoritative N38/BT/RNG parity and actual source tick versus request/FrameView elapsed timing. Do not equate phase call samples with paid ticks.
