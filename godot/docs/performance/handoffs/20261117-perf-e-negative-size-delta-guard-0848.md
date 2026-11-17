# PERF E handoff · 2026-11-17 · negative size delta guard

- Branch: `integration/perf-astra-5-workers-20261116`; PR #262, no merge.
- Code commit: `e393f693217f0378bb2f804bc0e2551e4899347e` — `godot/scripts/sim/phase2/n158_worker_request_metrics.gd`.
- Test commit: `45452d86b7b03cf00dabb74eddeb8a3b2b739b1a` — `godot/tests/p2_perf_e_size_delta_negative_guard_20261117.gd`.
- Change: count_delta rejects negative primitive source counts in either checkpoint. Legitimate negative signed deltas caused by cleanup remain supported.
- TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No FPS/TPS claim or measured improvement. Existing CI #43972442164 predates this patch.
- Safety: no authoritative N9/N39/N38/N158 mutations, no RNG/BT/SourceClock/cadence changes; only diagnostic acceptance.
- NEXT: run targeted E regression and bounded same-seed late paid tick profile (100/300/600/900), comparing exact N38/BT/RNG and wall request/projection vs paid tick timing; no 2600/35min CI.
