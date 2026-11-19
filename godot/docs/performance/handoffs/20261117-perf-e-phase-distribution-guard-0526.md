# PERF E — phase distribution acceptance guard (17.11.2026)

- Branch: `integration/perf-astra-5-workers-20261116`; draft PR #262; no merge.
- Code commit: `b6f9d298401b12dfff34b8d60a5a00a1a4772d86`.
- Test commit: `28a2fb4900a8311a18c2be98bb820366be3ed108`.
- Files: `godot/scripts/sim/phase2/n158_worker_request_metrics.gd`, `godot/tests/p2_perf_e_phase_distribution_guard.gd`.
- Correctness: comparator now rejects impossible phase distributions even when total/mean match: maximum must not exceed total, and for 100 non-negative samples the nearest-rank p95 (index 94) implies total >= maximum + 5*p95. No simulation, worker, UI, N9, N39, N38, balance, RNG or cadence changes.
- TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. Existing CI #43972442164 PASS predates this change; no new runtime speedup claimed.
- Limitation: this hardens the detached comparator, not the still-missing direct per-paid-tick phase measurement wiring. The external fingerprint remains an authoritative caller responsibility.
- Next: attach real paid-tick phase durations from existing N158/N39 profiling at the authoritative commit boundary, then bounded same-seed 100/300/600/900 windows and N38/BT/RNG parity (CI <=12 min). Do not repeat 99ab25e9 or 1676db61.
