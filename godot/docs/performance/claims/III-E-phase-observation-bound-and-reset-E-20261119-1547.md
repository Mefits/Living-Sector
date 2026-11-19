# Astra III/E — bounded paid phase observation and invalidation
STATUS: IN_PROGRESS
OWNER: E
START: 2026-11-19 15:47 MSK
BASE_SHA: e54678dbf6d9a32a2f7f15ae487c69e678e4f0b0
ASTRA: N158 bounded profiling counters, phase/callsite true paid-tick acceptance and negative/oracle fixtures.
INTENDED_FILES: godot/scripts/sim/phase2/n158_timed_phase_probe.gd; godot/tests/p2_perf_e_phase_observation_bound_reset.gd
EXPECTED: enforce finite per-tick sample budget, reject partial/overflowed windows, reset stale accumulated evidence on restart/rewind; preserve source execution and exact phase timing for accepted windows.
TEST: NOT_RUN
