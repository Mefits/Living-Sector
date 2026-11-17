# PERF E — bounded N39 diagnostic samples (17.11.2026)

Branch: `integration/perf-astra-5-workers-20261116`; PR #262; no merge.

## Code
- `aa2a4365cb2604b6377031551a99684f0ce35595` — `godot/scripts/sim/phase1/n39_native_world_production.gd`: retain only last 256 elapsed-usec samples per copy/schema site. Lifetime calls, total, min, max remain exact; p50/p95/p99 refer to last 256 samples, not all historical samples. Profiling remains opt-in.
- `8bf20cd071081618efc6d26b4323df19d798f064` — `godot/tests/p2_perf_e_n39_bounded_profile.gd`: 1024 calls, 256 retained, exact total and extrema, independent site, p95=1012 and no published sample array.

TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No Godot execution or benchmark in this shift. No claimed TPS/FPS improvement; effect is bounded diagnostic retention under `LS_PROFILE_NATIVE_PHASES=1`, not production tick optimization. Does not change World, N9, N38, BT, RNG or cadence.

Prior CI #43972442164 PASS covers earlier HEAD only, not these commits. Do not repeat 99ab25e9 / 1676db61.

Next: run targeted Godot regression and bounded same-seed late phase profiler up to 900 paid ticks within 8–12 minutes, compare N39 deep site totals and phase costs; check N38/BT/RNG exact snapshots before accepting any production speed claim.
