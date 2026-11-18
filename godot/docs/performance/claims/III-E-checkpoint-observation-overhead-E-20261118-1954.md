# Astra III/E — bounded checkpoint/observer overhead
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: E
START: 2026-11-18 19:54 MSK
BASE HEAD: 5cbea9b1a24da75c0f451beefb09c4d12be6209a
SOURCE: ASTRA_FIVE_SHIFTS_RU.md — E separate paid-tick cost, worker request, DTO/projection and benchmark measurement overhead; bounded windows and parity.
INTENDED: godot/tests/p2_perf_e_real_direct_threaded_oracle.gd; godot/scripts/sim/phase2/n158_direct_threaded_acceptance.gd; godot/tests/p2_perf_e_checkpoint_observation_overhead.gd.
RESULT: measure detached direct and worker checkpoint wall time outside paid-tick windows at real milestone ticks, validate attribution, bounded per-milestone reporting, preserve exact parity and restart. Positive and negative oracle regression. No CI.

END: 2026-11-18 19:54 MSK
CODE SHA: d0f77bfa4434c8bf80b2cae2c5b522ffc15d0a3e, fc2b96f92d5280b871704bf718214024054f5581, 7f5a90c5a0b15975845fa5edaed028a96fb91e9c
TEST SHA: 407b433ffd0a03ce5744c407f9a257dde89e9f6e
FILES: n158_direct_threaded_acceptance.gd; p2_perf_e_real_direct_threaded_oracle.gd; p2_perf_e_checkpoint_observation_overhead.gd
IMPLEMENTED: actual detached checkpoint creation and owner request wall time at fixed real paid-tick milestones; separate from per-tick advance/projection windows. Strict parity before accepting samples; fixed target milestone coverage; bounded detached totals/maxima; explicit elapsed-not-CPU and no performance claim.
TEST: NOT_RUN / CODE_UNVERIFIED / PERFORMANCE_NOT_MEASURED. Positive: exact checkpoint timing, total, independent copies. Negative: RNG divergence, wrong tick, negative time, missing/duplicate/reversed milestone, false paid-tick attribution.
RISK: execution and runtime cost unverified; no Godot/Actions run. Worker request includes FIFO/poll latency, not CPU. No change to N9/N38/N39/BT/RNG or production behavior.
NEXT ASTRA E: integrate actual phase/callsite measured timings into the same bounded direct/thread acceptance at windows 100/300/600/900, preserving detached source parity; run targeted test only when authorized.
