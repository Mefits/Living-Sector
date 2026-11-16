# PERF E — bounded paid-tick wall attribution (16.11.2026)

Branch: `integration/perf-astra-5-workers-20261116`; draft PR #262.

Code SHA: `92bb2c3897571ac66f3aa1a5451557f8e47e3662`.
Test SHA: `16296c42729feba5f3119d85704f82ac564c4c22`.

Files:
- `godot/scripts/sim/phase2/n158_worker_request_metrics.gd`: bounded exact-window (100/300/600/900) average and p95 elapsed advance, projection, and full request for individually attributable paid ticks; rejects multi-tick, zero-tick, malformed or out-of-order entries; explicit elapsed-wall-not-CPU marker.
- `godot/tests/p2_perf_e_paid_tick_window_attribution.gd`: deterministic positive 100-tick arithmetic and negative missing/duplicate/multi/zero/corrupt cases.

TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No local Godot and no CI dispatched. No speedup claimed; no fresh TPS/FPS measurement. No balance, World, N9, N38, worker scheduling or UI changes.

Important: this method is deliberately a pure calculation within the existing E metrics module. It does NOT itself sample real paid ticks. It cannot establish CPU usage: existing timestamps are elapsed wall. To avoid misleading data, do not report a complete window unless 100 consecutive individually timed paid ticks are present. Multi-tick worker requests need native per-source-tick timing, not division by count.

NEXT: instrument actual authoritative source-tick boundary (not request count), feed detached primitive timing rows to this aggregator, and connect real receipt/contract/dock/event/ship counts to checkpoint_counts after commit. Compare phase cost and counts on same frozen seed at 100/300/600/900, with bounded CI ≤12 minutes and full N38/BT/RNG parity before accepting runtime changes.
