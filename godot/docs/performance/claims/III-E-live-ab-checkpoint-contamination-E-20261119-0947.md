# Astra III/E — live A/B checkpoint contamination control
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: E
DATE: 2026-11-19 09:47 MSK
BASE SHA: 2317c3f283af71bfabff5dc83993eedb2749ca99
ASTRA BACKLOG: bounded same-seed profiling and measured profiler overhead, exact N38 parity.
CLAIM SHA: 735e2f26d8caabea7b40f8e6fa18de618a24fb66
CODE SHA: 0122ef4f62ce544a532dc971d5d83f35ab062c0f, 8f64929d4abccddf6c4a067467aeed6a79e558b7, 903c02d025d3f7b292dec863de71510c6ddf01ca
TEST SHA: 68daa5234c3165630bea751430334ef4dd2f38c5
FILES:
- godot/scripts/sim/phase2/n158_instrumentation_ab_acceptance.gd
- godot/tests/p2_perf_e_live_instrumentation_ab.gd
- godot/tests/p2_perf_e_ab_periodic_checkpoint_oracle.gd
RESULT: real live paired paid-tick benchmark now checkpoints every 10th tick, with strict full-state oracle at every gate and at window end. The comparator enforces complete gate coverage, rejects unexpected/missing checkpoints, failed paid ticks, invalid clocks and forged reports. Existing strict per-tick mode remains default for other callers. Every paid tick still executes; no simulation tick is skipped. This reduces intrusive full checkpoint work from 100 to 10 per 100-tick measurement window; does not prove lower wall time or CPU usage.
TEST: NOT_RUN (Godot runtime not invoked; GitHub Actions prohibited). CODE_UNVERIFIED / PERFORMANCE_NOT_MEASURED.
NEXT ASTRA E: compare strict-vs-periodic checkpoint modes under identical seed with independent runs; quantify checkpoint observation contamination, retain exact N38 parity at gates, then agree on A/B copy/Schema/N9 scalar probes.
