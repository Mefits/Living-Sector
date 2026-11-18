# Astra III/E — cadence-aware paid phase callsite coverage
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: E
START: 2026-11-18 21:49 MSK
BASE SHA: acff191cc309d59ebace06092c2dbb1465f003ee
ASTRA: E bounded paid tick profiling, per-phase callsite count/time, exact direct/thread comparator; do not mislabel sparse cadence as missing ticks.
INTENDED FILES: godot/scripts/sim/phase2/n158_timed_phase_probe.gd; godot/scripts/sim/phase2/n158_direct_threaded_acceptance.gd; godot/scripts/sim/phase2/n158_real_owner_thread_probe.gd; godot/tests/p2_perf_e_real_direct_threaded_oracle.gd; new targeted E regression.
EXPECTED: 100 contiguous authoritative paid ticks, phase call count including zero-cadence ticks, elapsed phase distributions and independent direct/thread validation, negatives for forged/missing/overcounted callsites; no default UI or source changes.
TEST: NOT_RUN

CODE SHA: cce645f9a126b7190c4bb0cd2167233dd25bfd14; 18c56cb1c3485ed54d9ad0ff1aa496fea272a408
TEST SHA: 0784deb4e402d10e2eb7e2cf93389fd77e5bf16a
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED
SOURCE: n158_timed_phase_probe.gd _record_phase_elapsed, paid_phase_window, paid_phase_totals, paid_phase_distribution; n158_direct_threaded_acceptance.gd verify_paid_phase_pair and compare_phase_callsite_coverage.
EFFECT: Cadence-sparse source phase observations now occupy zero-call paid-tick slots; independent SourceClock/committed checkpoint remains mandatory; direct and threaded phase call counts and active paid ticks must agree, wall time may differ. Instrumentation remains bounded to 100 paid ticks, with negative aborted/missing/forged coverage.
NEXT ASTRA E: bounded per-callsite N158 copy/Schema/N9 counts with same-seed early/late overhead comparison; preserve checkpoint parity and avoid adding instrumentation to A/B/C/D-owned source.
RISK: Godot parser and runtime not executed. Phase coverage gate requires each of four phases observed at least once per 100-tick window; source cadence must be confirmed at manual execution.
