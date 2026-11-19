# Astra III/E — bounded paid-window tail latency and process memory attribution
STATUS: IN_PROGRESS
OWNER: E
START: 2026-11-19 03:46 MSK
BASE_SHA: 90e87c0a6a37aaf8a298deaef5783a12c2c08445
ASTRA: ASTRA_FIVE_SHIFTS_RU.md / E measurement: bounded same-seed paid tick p50/p95/p99, RSS/allocated memory; distinguish request wall from paid tick and CPU.
INTENDED_FILES:
- godot/scripts/sim/phase2/n158_paid_window_resource_probe.gd (new)
- godot/tests/p2_perf_e_real_direct_threaded_oracle.gd
- godot/tests/p2_perf_e_paid_window_resource_regression.gd (new)
ACCEPTANCE: 100 paid ticks per window, strict contiguous SourceClock, exact checkpoint gate, detached scalar memory sample, p50/p95/p99, monotonic window bounds, positive/negative oracle and no CPU claim.
TEST: NOT_RUN
