# Astra III/E — bounded observation callsite attribution
STATUS: IN_PROGRESS
OWNER: E
START: 2026-11-19 00:45 MSK
BASE SHA: ad277079f8556372c688779aee552c50b2c3eb15
ASTRA: E measured overhead, bounded N158 early/late profiling; separate real checkpoint copying/serialization from paid ticks and worker request.
INTENDED: godot/scripts/sim/phase2/n158_direct_threaded_acceptance.gd; godot/scripts/sim/phase2/n158_observation_cost_acceptance.gd; godot/tests/p2_perf_e_observation_cost_oracle.gd
CHECK: exact milestone/callsite coverage, additive timing, positive/negative oracle, no World alias, no CI.

STATUS: CODE_DONE_TEST_UNVERIFIED
CODE SHA: f51035c6f72a85a4405d3ffe90f788a8b4ed098e, cc401a808125d68a245c56b09af2aec5b5aa9ee0
TEST SHA: c47a17ac46f327aef57258ebcfbbb9350649d65a
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED
FILES: n158_observation_cost_acceptance.gd, p2_perf_e_real_direct_threaded_oracle.gd, p2_perf_e_observation_cost_oracle.gd
RESULT: Actual direct checkpoint, worker checkpoint request, exact parity oracle, N39 size oracle, and N9/events oracle wall durations recorded outside paid-tick windows at real checkpoint callsites. Exact-gated bounded scalar summaries, early/late deltas and negative cases; no live World references retained.
RISK: Unexecuted Godot parser/runtime and 900-tick budget. Timing is wall elapsed, not CPU; no speedup claim.
NEXT ASTRA E: measured snapshot/schema/N9 inner callsite costs in N158 using owner-approved scalar probe interfaces, without editing A/B-owned files; targeted oracle and same-seed 100/300/600/900.
