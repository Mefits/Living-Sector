# Astra III/E — bounded checkpoint/observer overhead
STATUS: IN_PROGRESS
OWNER: E
START: 2026-11-18 19:54 MSK
BASE HEAD: 5cbea9b1a24da75c0f451beefb09c4d12be6209a
SOURCE: ASTRA_FIVE_SHIFTS_RU.md — E separate paid-tick cost, worker request, DTO/projection and benchmark measurement overhead; bounded windows and parity.
INTENDED: godot/tests/p2_perf_e_real_direct_threaded_oracle.gd; godot/scripts/sim/phase2/n158_direct_threaded_acceptance.gd; godot/tests/p2_perf_e_checkpoint_observation_overhead.gd.
RESULT: measure detached direct and worker checkpoint wall time outside paid-tick windows at real milestone ticks, validate attribution, bounded per-milestone reporting, preserve exact parity and restart. Positive and negative oracle regression. No CI.
