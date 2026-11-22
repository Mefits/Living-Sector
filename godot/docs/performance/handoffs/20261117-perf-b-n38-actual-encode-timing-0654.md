# PERF B · N38 actual encoding cost (17.11.2026)

Branch: `integration/perf-astra-5-workers-20261116` / PR #262.

- CODE: `337e9533244b82c28d4e2fd672407972b6eed75a` — `godot/scripts/sim/save_state.gd`.
- TEST: `c3313e806693c739416819fa63d60791c31005f5` — `godot/tests/p2_perf_b_n38_actual_encode_timing_20261117.gd`.
- TEST EXECUTED: **NOT RUN**; **CODE_UNVERIFIED / TEST_ADDED_NOT_RUN**.
- N38 now records `last_save_encode_usec()` alongside the existing exact `last_save_encoded_bytes()`, timed strictly around the actual `_encode_checkpoint_text(snapshot).to_utf8_buffer()` in `save_runner()`. No second serialization, no World scan, no new format, no 16 MiB limit change, no new disk writes. Rejected preflight leaves both measurements unchanged.
- Negative regression checks that a rejected unstarted runner cannot manufacture timing/bytes and diagnostic reads are side-effect-free; also checks Unicode byte accounting.
- Performance improvement: **NONE CLAIMED**. The measurement is wall microseconds of N38 encoding during an actual save, **not CPU ms per paid tick**. No receipt count, 100/300/600/900 data, p95 or long soak available in this shift.
- Next: collect this metric and actual saved byte sizes at existing 100/300/600/900 checkpoints, plus receipt counts from existing snapshots without per-tick serialization. Correlate N9 paid receipt growth and real call counts with E's phase profiler before changing retention. Preserve exact N9/N39/N38/BT/RNG/cargo parity.
- Do not duplicate `99ab25e9` (N9 WeakRef) or `1676db61` (N158 projections). No N39/N152 changes. No CI launched.
