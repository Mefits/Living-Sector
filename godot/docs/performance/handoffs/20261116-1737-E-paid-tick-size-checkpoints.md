# PERF E — paid-tick size checkpoints (2026-11-16 17:37 CET)

Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262.

Code commit: `93ac99934f75ac98e453694b5645180705e86c79`.
Test commit: `1a18815f653bfbe2c8a2a3ff77e0f2b6ff0e9423`.

Files:
- `godot/scripts/sim/phase2/n158_worker_request_metrics.gd`: checkpoint_counts at paid ticks 100/300/600/900; strict nonnegative integer counts for receipts/contracts/dock/events/ships; signed count_delta. Pure, bounded, detached dictionaries only.
- `godot/tests/p2_perf_e_paid_tick_size_checkpoint.gd`: negative invalid tick, missing key, negative count, reverse comparison; zero-paid-tick request exclusion.

TEST: NOT RUN; CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No runtime acceleration or new FPS/TPS measurement. Existing worker request elapsed metrics remain unchanged. No simulation behavior, SourceClock, N38 or ownership modified.

**Limitation:** checkpoint counters are an extension of the existing connected request metrics module, but the authoritative worker has not yet supplied the five counts; do not claim real growth samples until integrated. Next code step: inspect authoritative committed World/ledger container names and add opt-in owner-side primitive count capture at ticks 100/300/600/900, then compare same-seed early/late counts against phase costs (ships/dock/markets/factions), without copying World or accessing SceneTree from worker. Keep CI <=12 minutes.
