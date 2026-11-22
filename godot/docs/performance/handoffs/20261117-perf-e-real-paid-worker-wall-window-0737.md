# PERF E — real paid worker wall windows (17 Nov 2026)
Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262.
Code commit: `43e66ebca7f5eeaeb83085d0c4a6a965d0974451`.
Test commit: `c9ddccf463cb3e60b32e292efb9d341f322d3ac1`.

Files: `godot/scripts/sim/phase2/n158_real_owner_thread_probe.gd`; `godot/tests/p2_perf_e_real_paid_window_20261117.gd`.

Worker now collects detached monotonic wall elapsed timings for the last 100 successful **single paid tick** requests. At 100/300/600/900 it emits `paid_tick_window` with separate advance/projection/request averages and advance p95. A multi-tick request or load/restore invalidates coverage; no false attribution to CPU or FPS. Only bounded scalar data retained, no extra World snapshot, no changes to source simulation, balance, N9, N39, UI or worker scheduling.

TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. Previous CI #43972442164 PASS predates this code. No performance gain claimed.

Caveat: this is request elapsed wall time, not actual CPU paid tick or native phase breakdown. Window only completes if 100 consecutive requests each pay exactly one tick; otherwise an empty window is honest. Next: wire real native phase per-paid-tick samples at source boundary, short <=900 same-seed profile with N38/BT/RNG parity, no 2600/35-minute CI.
