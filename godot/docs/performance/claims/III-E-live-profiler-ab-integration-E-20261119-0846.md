# Astra III/E — live independent N158 profiler on/off A/B
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: E
TIME: 2026-11-19 08:46 MSK
BASE HEAD: 9d103a08ca5942a0a8d3b25ec7f71d1a8b7853fb
CLAIM SHA: 1091f3d17e2901e8735e88245b362ea364161872
CODE SHA: 5bb59d76a2a58fc8536e704daf1c0c12a2671484
TEST SHA: 8f3dbc272fb77a5ebb59bc74995ecce158dd1ba4
SOURCE: ASTRA_FIVE_SHIFTS_RU.md — E bounded paid-tick benchmarking and measured profiler overhead, continuing III-E-instrumentation-ab-overhead-E-20261119-0751.
FILES:
- godot/tests/p2_perf_e_live_instrumentation_ab.gd
- godot/tests/p2_perf_e_live_instrumentation_ab_negative.gd
RESULT: Real executable headless SceneTree harness now boots independent same-seed uninstrumented N158 production and instrumented N158 timed phase probe, pauses both and executes every paid tick in both arms (including 101–200 and 301–500 warmup), alternating measured arm order for 100-tick windows ending 100/300 and opt-in 600/900. Every measured tick is gated by full detached checkpoint comparison (N39/N9/BT/RNG/cargo/contract fields are not filtered); boundaries are rechecked independently; profiled phase coverage must be real and complete. Bounded wall-time fail-closed. Source tick time excludes detached checkpoint/comparison overhead. Negative oracle checks cargo/ledger/RNG/BT/World divergence, failed tick, clock, malformed timing and missing checkpoint. No production economy, N39, N9, N38, worker UI or foreign owner files edited.
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED.
LIMITATIONS: The measured metric is elapsed wall-time delta between profiler-on and profiler-off; isolated profiler bookkeeping microseconds are not exposed by N158, so instrumentation_usec=0 is an unknown/unmeasured component, NOT proof of zero overhead. Checkpoint per tick is expensive and may perturb cache/GC; this is correctness-gated diagnostic, not pure CPU benchmark. No Windows/Godot execution in this run. Extended 900-tick mode opt-in only.
NEXT: run Godot parser and targeted negative/live A/B on same Windows build and seed, then instrument isolated profiler bookkeeping cost and/or repeat interleaved A/B trials to quantify variance, retaining exact N38 restart and parity gates.
