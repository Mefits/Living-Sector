# Astra III/E — bounded observation callsite attribution
STATUS: IN_PROGRESS
OWNER: E
START: 2026-11-19 00:45 MSK
BASE SHA: ad277079f8556372c688779aee552c50b2c3eb15
ASTRA: E measured overhead, bounded N158 early/late profiling; separate real checkpoint copying/serialization from paid ticks and worker request.
INTENDED: godot/scripts/sim/phase2/n158_direct_threaded_acceptance.gd; godot/scripts/sim/phase2/n158_observation_cost_acceptance.gd; godot/tests/p2_perf_e_observation_cost_oracle.gd
CHECK: exact milestone/callsite coverage, additive timing, positive/negative oracle, no World alias, no CI.
