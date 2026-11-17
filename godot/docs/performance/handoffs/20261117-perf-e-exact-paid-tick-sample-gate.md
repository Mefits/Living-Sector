# PERF E — exact paid tick sample gate (17.11.2026)

Branch: `integration/perf-astra-5-workers-20261116`; draft PR #262.

Code: `c3ca94a82614b2d480ddfd66c2fbd05024a59930` (strict detached sample validator), `46064e1993718fed24806b5d218f701c1bd38824` (authoritative owner integration).
Test: `31541e6db1613b574ddf748a9b73ff54b6bc5a3b` (positive + negative cases).

Files: `godot/scripts/sim/phase2/n158_worker_request_metrics.gd`, `godot/scripts/sim/phase2/n158_real_owner_thread_probe.gd`, `godot/tests/p2_perf_e_exact_paid_tick_sample_20261117.gd`.

A 100-request window must only admit actual consecutive single-paid-tick requests with consistent detached wall-clock attribution. The owner now checks the source tick boundary and the sample's detached arithmetic before appending it. This is a measurement-integrity fix, **not** a performance improvement.

TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No Godot runtime execution or fresh performance benchmark. CI #43972442164 predates these commits. No N39/N9/ships/Head, gameplay cadence, RNG, balance, UI, or worker scheduling changes.

Next: bounded headless profiling at paid ticks 100/300/600/900 with source checkpoint parity, distinguishing request elapsed from paid-tick and diagnostic overhead. Do not claim CPU timing from elapsed wall measurements. Do not rerun 2600-tick soak or 35-minute CI.
