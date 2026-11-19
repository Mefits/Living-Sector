# Astra III/E — bounded paid-window tail latency and process memory attribution
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: E
START: 2026-11-19 03:46 MSK
BASE_SHA: 90e87c0a6a37aaf8a298deaef5783a12c2c08445
ASTRA: ASTRA_FIVE_SHIFTS_RU.md / E measurement: bounded same-seed paid tick p50/p95/p99, RSS/allocated memory; distinguish request wall from paid tick and CPU.
INTENDED_FILES:
- godot/scripts/sim/phase2/n158_paid_window_resource_probe.gd (new)
- godot/tests/p2_perf_e_real_direct_threaded_oracle.gd
- godot/tests/p2_perf_e_paid_window_resource_regression.gd (new)
ACCEPTANCE: 100 paid ticks per window, strict contiguous SourceClock, exact checkpoint gate, detached scalar memory sample, p50/p95/p99, monotonic window bounds, positive/negative oracle and no CPU claim.
CODE_SHA: 2634bbf8760d2af0975f21bd5408f324a04bce90, ca419bf491fe4911f53709edb7a3cc18c188c2fa
TEST_SHA: cee019ee0ad2da9429d879e98215acd4c0b4ed36
TEST: NOT_RUN (Godot unavailable in this run; no Actions)
RESULT: 100 exact paid tick samples, direct/worker advance/request/projection p50/p95/p99/max/avg; same-seed checkpoint parity gate; shared-process static allocator and peak, explicitly not RSS or per-worker memory. Early/late delta and adjacent window comparisons. No World aliases retained. Positive/negative oracle for clock gaps, forged tails, impossible memory, missing parity, overlapping windows.
NEXT: obtain true process RSS/CPU counters using a platform-supported provider and validate against same-seed 100/300/600/900 on Windows; coordinate internal copy/Schema/N9 counters with A/B without editing their files.
CODE_UNVERIFIED / PERFORMANCE_NOT_MEASURED
