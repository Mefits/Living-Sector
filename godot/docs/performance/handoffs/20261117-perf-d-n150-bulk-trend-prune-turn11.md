# PERF D — N150 bulk trend pruning (17.11.2026)

CODE: 44a4779e8a3b5d3eb501a84b0e1fec66b9da0a85
TEST: b025ea5f6617ff034bdebb3c253a342dcf1453c6

Files: godot/scripts/sim/phase1/n150_native_full_market_tick.gd; godot/tests/p2_perf_d_n150_trend_bulk_prune_20261117.gd.

On the live N150 trend-sampling path, replace repeated Array.pop_front() for overlong restored trend histories with one Array.slice() retaining exactly the latest MARKET_TREND_KEEP entries. This avoids repeated shifts when an input history is much larger than the source cap; ordinary capped history remains unchanged. Input market is deep-copied before this step. New negative oracle checks 1000 old entries, chronological order, source detachment and non-sampling cadence.

Status: CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No Godot runtime or same-seed CPU profile executed; benefit on ordinary 200-entry histories is expected to be negligible. No claims about solving late-tick slowdown. CI deliberately not triggered. N9/N39/N152/N158 untouched.

Next: run targeted oracle in shared bounded checkpoint; profile N150 time and actual trend lengths early/late before any further N150 changes. If trend length remains <=200, prioritize larger measured market/Head costs rather than this branch.
