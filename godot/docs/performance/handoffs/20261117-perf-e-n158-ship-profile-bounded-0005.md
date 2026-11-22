# PERF E handoff — 2026-11-17 — bounded N158 ship subphase profiler

Branch: `integration/perf-astra-5-workers-20261116`; PR #262 only.

- Code: `e65bbd1ec20da67a8cddba441384b64aba737206` — `godot/scripts/sim/phase2/n158_production_runtime.gd`. Opt-in `_profile_ship_samples` now retains only the latest 256 elapsed samples per stage. The existing p95/average/max/total/calls are explicitly **window statistics**, not cumulative lifetime statistics; `window_limit` is reported. No World, N9, SourceClock, N38, BT or RNG writes.
- Test: `2a131f75c61f263679f51a03270f8a7ac4d89f0d` — `godot/tests/p2_perf_e_ship_profile_bounded.gd`; checks 1024 appends, oldest eviction, ordering, negative elapsed clamp.
- TEST: NOT RUN (Godot runtime not invoked). CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No measured TPS/FPS gain. This bounds diagnostic retained sample memory only; `pop_front` is O(256), constant bounded.
- Existing acceptance: CI #43972442164 PASS at its recorded SHA; **does not validate these new commits**. Long-run Windows/900/2600 parity remains open.
- Next concrete E step: bound N39 copy/schema profiling arrays with a documented rolling p95, targeted test, then run a single short parity/profile acceptance on a coordinated checkpoint (<=12 minutes).
