# Astra III/E — bounded paid phase observation and invalidation
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: E
START: 2026-11-19 15:47 MSK
BASE_SHA: e54678dbf6d9a32a2f7f15ae487c69e678e4f0b0
ASTRA: N158 bounded profiling counters, phase/callsite true paid-tick acceptance and negative/oracle fixtures.
INTENDED_FILES: godot/scripts/sim/phase2/n158_timed_phase_probe.gd; godot/tests/p2_perf_e_phase_observation_bound_reset.gd
EXPECTED: enforce finite per-tick sample budget, reject partial/overflowed windows, reset stale accumulated evidence on restart/rewind; preserve source execution and exact phase timing for accepted windows.
CODE_SHA: ec24c9ab5b0116c3aba019b695773e5acfc75ac6, 67ae1d8dc03bf1e1d63d086c026a36e67b392bfd
TEST_SHA: 3f9c2e4bdfb9c13a8e4b2567f9383f7464292cdc
TEST: NOT_RUN / CODE_UNVERIFIED / PERFORMANCE_NOT_MEASURED
IMPLEMENTED: bounded per-tick phase samples (64), total retained cap, eviction accounting, invalidation on overflow/failed phases and clock rewind; negative/positive headless oracle.
RISK: no Godot runtime execution; benchmark windows and full N38 parity remain unverified.
NEXT ASTRA E: connect authoritative N39/Schema/N9 copy counters through A/B-owned read-only interfaces and compare early/late paid windows without extra World snapshots.
