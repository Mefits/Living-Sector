# PERF E handoff — 2026-11-16 16:56 CET

Scope: isolated, opt-in existing N158 worker request measurement. No worker/UI rewrite, no World/N9/Clock/N38 or balance changes.

Commits:
- 098d958d6f4f56ddf43c382e3cfc3fdcabdcb3c9 — n158_worker_request_metrics.gd
- 31cb1ee17861cec99b11452f78174989de399cbb — n158_real_owner_thread_probe.gd integration
- 3b413dd936f960b3d3473e44b5aab812d66ce9ea — p2_perf_e_worker_request_timing_boundary.gd

The real worker reply now includes timing.paid_ticks, advance_wall_usec, projection_wall_usec, request_wall_usec and advance_wall_usec_per_paid_tick. A request with zero paid ticks has per-paid-tick = -1. Negative tick deltas or non-monotonic timestamp order are rejected. Timing is monotonic *elapsed wall time*, not thread CPU time; advance includes command processing, so do not call it pure source phase CPU. Projection includes orbital/economy/observer DTO creation when requested. Existing sim_usec remains for compatibility. No mutable simulation aliases escape.

TEST: NOT RUN (Godot 4.7.2 unavailable here). CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No FPS/TPS or speedup claimed. No CI triggered.

Next concrete code: in E-owned bounded same-seed harness, record the new timing fields separately for exactly paid ticks at 100/300/600/900 and correlate with A/C/D phase counts and receipts/contracts/dock/events sizes. Avoid 2600-tick or 35-minute jobs; cap to 8–12 minutes. Validate N38 restart/checkpoint parity before accepting a behavioral optimization.
