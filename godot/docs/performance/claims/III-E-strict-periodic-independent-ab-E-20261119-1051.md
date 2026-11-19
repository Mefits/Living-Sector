# Astra III/E — independent strict versus periodic N158 A/B
STATUS: IN_PROGRESS
OWNER: E
DATE: 2026-11-19 10:51 MSK
BASE SHA: b0ab88d12bfa916ccd73e52a2dc12de5968e505c (last known E claim; concurrent HEAD to be rechecked)
ASTRA BACKLOG: E bounded same-seed paid-tick profiling, profiler overhead, exact N38 parity.
TASK: independently seed and execute strict every-tick and periodic checkpoint observation modes; compare equal paid tick windows without counting checkpoint time as CPU, ensure full-state gates and negative/oracle fixtures.
INTENDED FILES: godot/scripts/sim/phase2/n158_instrumentation_ab_acceptance.gd; godot/tests/p2_perf_e_live_instrumentation_ab.gd; godot/tests/p2_perf_e_strict_periodic_mode_oracle.gd.
EXPECTED TEST: valid matching independent windows accepted; mismatched ticks, strides, gates, forged totals rejected. Runtime NOT RUN until manual Godot.
RISKS: sequential runs differ due to machine load; wall time not CPU; no causal acceleration claim.
