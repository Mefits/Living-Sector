# Astra III/E — independent strict versus periodic N158 A/B
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: E
DATE: 2026-11-19 10:51 MSK
BASE SHA: b0ab88d12bfa916ccd73e52a2dc12de5968e505c (last known E claim; concurrent HEAD to be rechecked)
ASTRA BACKLOG: E bounded same-seed paid-tick profiling, profiler overhead, exact N38 parity.
TASK: independently seed and execute strict every-tick and periodic checkpoint observation modes; compare equal paid tick windows without counting checkpoint time as CPU, ensure full-state gates and negative/oracle fixtures.
INTENDED FILES: godot/scripts/sim/phase2/n158_instrumentation_ab_acceptance.gd; godot/tests/p2_perf_e_live_instrumentation_ab.gd; godot/tests/p2_perf_e_strict_periodic_mode_oracle.gd.
EXPECTED TEST: valid matching independent windows accepted; mismatched ticks, strides, gates, forged totals rejected. Runtime NOT RUN until manual Godot.
RISKS: sequential runs differ due to machine load; wall time not CPU; no causal acceleration claim.

CLAIM SHA: bb327d35ed5e87d16f6b309677bd3d72ea73d15a
CODE SHA: 1b80fdf903fd9f75b30ae473f7f2cf544a9c4ce2, fe48cdb009036ebc5b47cb7587b6785c1aa07aee, 3c4d6145ae075a4d49bc75102d6fb61e3c5c9cfc
TEST SHA: b01894df119f9f525b9008133d37d4da47becc54
RESULT: Existing real N158 live A/B now executes two independent seed-initialized direct/profiled pairs, first strict per-paid-tick checkpoints, then periodic 10-tick checkpoints. Same 100/300 (optional 600/900) paid windows, no skipped ticks, exact full-state parity at every configured gate and final boundary. Comparator validates complete window bounds, non-overlap, accounting, gate coverage and both modes before reporting independent sequential wall-time differences. Checkpoint observation excluded from paid timing. No claim of CPU or causal speedup.
TEST: NOT_RUN; CODE_UNVERIFIED / PERFORMANCE_NOT_MEASURED. GitHub Actions not invoked.
NEXT ASTRA E: obtain manual same-seed Windows measurements and evaluate profiler-on/off phase overhead, then integrate bounded scalar A/B copy/Schema/N9 probes through owner-approved interfaces without modifying A/B files.
