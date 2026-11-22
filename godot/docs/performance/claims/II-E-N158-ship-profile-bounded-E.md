# II-E · N158 bounded ship profiler: paid-tick boundary integrity
STATUS: CODE_DONE_TEST_UNVERIFIED
Owner: E
Started: 2026-11-18 10:51 MSK
Base HEAD: fcce8fad71114e2f8c79f8eb8d8f0292d141c1ca
Source: ASTRA_FIVE_SHIFTS_RU.md, E bounded profiling / same-seed acceptance; 20261117 checkpoint.

Discovery: N158 already had SHIP_PROFILE_WINDOW=256 and bounded append, so no duplicate implementation. Remaining concrete defect: an unfinished stage begin could be paired with an end from a different paid tick, contaminating measured phase duration.

CODE SHA: 15cf9d8132ea9f8e8d6323d69e085101c5610086
TEST SHA: 9332a9eb86db4c80e02ff229ec7586a5dacba000
Files:
- godot/scripts/sim/phase2/n158_production_runtime.gd
- godot/tests/p2_perf_e_n158_ship_profile_tick_boundary.gd

Fix: record {tick,usec} at each N158 ship stage begin; only accept elapsed from matching tick and nonnegative timestamps, discard stale begin on end. The pre-existing bounded 256-sample window and stage publication are preserved. Diagnostic-only, no World/N9/N38 or simulation change.
Test: targeted positive same-tick, negative cross-tick/negative duration/missing begin, and 276-sample newest-window cap.
TEST EXECUTED: NOT_RUN; CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No CI triggered. No FPS/TPS gain claimed.
NEXT: execute targeted Godot test at next agreed acceptance checkpoint; compare 100/300/600/900 phase windows and exact N38/BT/RNG parity; measure real paid tick CPU separately from worker request elapsed.
