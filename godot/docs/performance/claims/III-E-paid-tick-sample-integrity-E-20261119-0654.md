# Astra III/E — paid tick sample integrity and bounded comparator
STATUS: IN_PROGRESS
OWNER: E
START: 2026-11-19 06:54 MSK
BASE_SHA: a542a5c2488caae5585bcabad390b58ba786ab5a
ASTRA: E bounded benchmarking protocol, same-seed direct/worker paid ticks and exact N38 parity.
INTENDED: godot/scripts/sim/phase2/n158_paid_tick_sample_integrity.gd; godot/tests/p2_perf_e_paid_tick_sample_integrity.gd; godot/tests/p2_perf_e_real_direct_threaded_oracle.gd.
GOAL: reject time-accounting discontinuities and malformed or aliased paid samples before any published late-window comparison, retaining only bounded scalar evidence. Positive/negative/oracle tests. No N39/N9/N38 edits.
TEST: NOT_RUN
