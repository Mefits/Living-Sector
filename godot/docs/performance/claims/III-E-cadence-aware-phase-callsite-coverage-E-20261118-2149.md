# Astra III/E — cadence-aware paid phase callsite coverage
STATUS: IN_PROGRESS
OWNER: E
START: 2026-11-18 21:49 MSK
BASE SHA: acff191cc309d59ebace06092c2dbb1465f003ee
ASTRA: E bounded paid tick profiling, per-phase callsite count/time, exact direct/thread comparator; do not mislabel sparse cadence as missing ticks.
INTENDED FILES: godot/scripts/sim/phase2/n158_timed_phase_probe.gd; godot/scripts/sim/phase2/n158_direct_threaded_acceptance.gd; godot/scripts/sim/phase2/n158_real_owner_thread_probe.gd; godot/tests/p2_perf_e_real_direct_threaded_oracle.gd; new targeted E regression.
EXPECTED: 100 contiguous authoritative paid ticks, phase call count including zero-cadence ticks, elapsed phase distributions and independent direct/thread validation, negatives for forged/missing/overcounted callsites; no default UI or source changes.
TEST: NOT_RUN
