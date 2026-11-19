# III/E — post-restart paid continuation parity
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: E
START: 2026-11-19 05:54 Europe/Moscow
BASE_SHA: 3e883f4e955947e14711ec0697185e3e283755b0
ASTRA: E N158 paid-tick benchmark, exact N38 restart, same-seed direct-vs-worker parity and bounded late-tick evidence.

CODE_SHA: 123d59f1a723489cf1960e9c59c71a889c14653a, 7458fb2c272a5a3ebab0492c4465c206af185de0
TEST_SHA: eb90a3c0a9d48037ff775829885836b070ad8689
TEST: NOT_RUN
VERIFICATION: CODE_UNVERIFIED / PERFORMANCE_NOT_MEASURED
FILES:
- godot/scripts/sim/phase2/n158_post_restart_paid_continuation.gd
- godot/tests/p2_perf_e_real_direct_threaded_oracle.gd
- godot/tests/p2_perf_e_post_restart_paid_continuation.gd

RESULT: Real same-seed N158 benchmark now restores both owners at a committed checkpoint and advances three subsequent paid ticks on each. It compares exact detached N39/N9/BT/RNG state on every resumed tick, validates worker paid step/source clock and elapsed attribution, and emits bounded scalar-only continuation evidence. Pre-restart 100-tick windows are not contaminated by continuation measurements. Positive and negative fixture rejects cargo/RNG/receipt divergence, skipped clock, invalid worker attribution, forged/gapped summary and unbounded continuation.

RISK: No Godot/Windows execution. Restore may reset paused/step controls differently on a live build; run targeted fixture and opt-in real owner benchmark manually. This is a correctness harness, not proof of performance gain.
NEXT ASTRA E: bounded actual internal copy/Schema/N9 instrumentation via A/B-provided read-only counters; compare early/late real paid windows on same seed and Windows build without claiming CPU/RSS from wall clock.
