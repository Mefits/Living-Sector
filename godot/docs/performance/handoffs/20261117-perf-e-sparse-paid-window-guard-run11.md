# PERF E · 17.11.2026 · bounded paid-tick window gap guard

Branch: `integration/perf-astra-5-workers-20261116` · draft PR #262.

CODE COMMIT: `93bdca7a29f112e8a327c54011864aff63d77c7c`
TEST COMMIT: `08f9c2e94414dcf29a8a9ecd2eedfc8d3e5ca833`

FILES:
- `godot/scripts/sim/phase2/n158_worker_request_metrics.gd`: reject input arrays larger than 100 and any gap in tick sequence. Only a contiguous prefix of checkpoint window can be reported as incomplete; a full window still needs all 100.
- `godot/tests/p2_perf_e_sparse_window_rejection_20261117.gd`: full, contiguous 99, internal gap, missing first tick, oversized 101.

TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN; no Godot execution or CI for these commits. Static code reviewed against existing `summarize()` and `bounded_paid_tick_window()` signatures.

WHY: Previous collector rejected duplicate/out-of-order ticks but could summarize sparse internal gaps as an incomplete window, and accepted unbounded input arrays. This closes diagnostic evidence ambiguity; **no simulation acceleration measured or claimed**. No changes to N39/N9/SourceClock/N38/BT/RNG, worker threading, UI, economic behavior, or Astra commits `99ab25e9`/`1676db61`.

NEXT: Run a single bounded, <=12-minute checkpoint with parser + targeted E regression and real N158 samples at 100/300/600/900 when feasible; verify source parity and keep request wall elapsed separate from CPU time.
