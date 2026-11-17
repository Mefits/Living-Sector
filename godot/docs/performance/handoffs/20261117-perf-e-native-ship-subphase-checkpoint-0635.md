# PERF E — 17.11.2026 — authoritative ship subphase checkpoint wiring

Branch: `integration/perf-astra-5-workers-20261116`, PR #262. No merge.

## Code commits
- `b3a440d0e5c2923661bcd5289c0799ca9da00f36` — E-owned `n158_worker_request_metrics.gd`: validate and detach existing bounded N158 ship-subphase profile samples, opt-in only; report actual calls, not fictitious 100-tick coverage.
- `5ecf376775e83965c9b96fd3ed57e5af80d5d7c6` — E-owned `n158_real_owner_thread_probe.gd`: read existing `sim.profile_native_ship_subphases()` at successful paid checkpoints 100/300/600/900 and attach detached report. No new worker, UI, source ticks or simulation mutations.
- `18a72c4252f8bdd481b7173a6694a598eb4a6d36` — `godot/tests/p2_perf_e_ship_subphase_checkpoint_evidence.gd`: bounded positive/negative regression, alias isolation, false profiling, bad averages and percentile.

## Verification
TEST_RUN: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. Existing CI #43972442164 PASS predates this change. No new FPS/TPS or late-tick speed measurement. This provides real wired diagnostic data only when `LS_PROFILE_NATIVE_PHASES=1` and a checkpoint is reached. `coverage=last_bounded_subphase_calls_not_paid_ticks` explicitly prevents equating profiler call counts to 100 paid ticks. Other phase durations and N9/event counts remain outstanding.

## Next
Run targeted Godot test and short bounded profile (up to 900 ticks, <=12 minutes) once coordinated; verify N38/BT/RNG exact parity and compare same-seed phase windows. Do not duplicate Astra 99ab25e9 / 1676db61 or modify worker/UI.
