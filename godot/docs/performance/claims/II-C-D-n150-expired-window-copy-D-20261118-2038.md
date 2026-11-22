# Astra II-C / D — N150 expired consumption-window copy boundary
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: PERF D
START: 2026-11-18 20:38 MSK
BASE SHA: 6e5deda971f3cda5576fc3e5e7613d39f57cb332
ASTRA: II-C station/faction/market rosters, repeated full scans and growing market histories; D markets 39.43s/300 ticks.
INTENDED FILES: godot/scripts/sim/phase1/n150_native_full_market_tick.gd; godot/tests/p2_perf_d_n150_window_copy_oracle.gd
PLAN: avoid deep-copying expired consumption samples that the paid N150 tick discards, while retaining validation of all samples, source order and float summation, ownership, demand/price and negative behavior. Target positive+negative old-vs-new oracle.
CODE SHA: 1364882998249ce8b55a3b74ed4069e3aaa63a93
TEST SHA: 861c2cf19880e0cb849b35556fb46f715b9c8a4f
FILES: godot/scripts/sim/phase1/n150_native_full_market_tick.gd; godot/tests/p2_perf_d_n150_window_copy_oracle.gd
FIX: Paid N150 tick validates every consumption row and deep-owns only retained window entries before cloning unrelated market fields; original per-slug compaction, demand summation, prices, ordering and result ownership remain. No persistent cache or new source of truth.
TEST: NOT_RUN (Godot unavailable; GitHub Actions deliberately not launched)
RISKS: runtime parser/behavior and late-tick improvement unverified; requires same-seed N150/N39/N9/N38 parity and phase benchmark.
NEXT: Astra II-C D — station/faction facility roster scans, invalidation across ownership/install/remove/move and exact Head/admin oracle.
