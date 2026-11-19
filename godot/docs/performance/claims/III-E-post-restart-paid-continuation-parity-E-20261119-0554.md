# III/E — post-restart paid continuation parity
STATUS: IN_PROGRESS
OWNER: E
START: 2026-11-19 05:54 Europe/Moscow
BASE_SHA: 3e883f4e955947e14711ec0697185e3e283755b0
ASTRA: E N158 paid-tick benchmark, exact N38 restart, same-seed direct-vs-worker parity and bounded late-tick evidence.
SCOPE: godot/tests/p2_perf_e_real_direct_threaded_oracle.gd; godot/scripts/sim/phase2/n158_post_restart_paid_continuation.gd; godot/tests/p2_perf_e_post_restart_paid_continuation.gd.
EXPECTED: after exact committed restart advance both real owners for bounded paid steps, reject source-clock/step divergence, compare exact checkpoint at each boundary; negative/oracle fixture and detached scalar summary. No CI.
