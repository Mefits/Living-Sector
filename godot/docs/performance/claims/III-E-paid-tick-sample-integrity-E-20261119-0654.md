# Astra III/E — paid tick sample integrity and bounded comparator
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: E
START: 2026-11-19 06:54 MSK
BASE_SHA: a542a5c2488caae5585bcabad390b58ba786ab5a
ASTRA: E bounded benchmarking protocol, same-seed direct/worker paid ticks and exact N38 parity.
CODE_SHA: 3b7cdfc84d943bd47ee3f511e9484c240f8b25f9, 7ed872e924ce8b0eb6e97a6b28db1bde425b0464
TEST_SHA: 8adafcfb872afb9bd9c5df42bf5ee467442f7a37
TEST: NOT_RUN
CODE_VERIFICATION: CODE_UNVERIFIED
PERFORMANCE: NOT_MEASURED

Changed source: n158_paid_tick_sample_integrity.gd; live p2_perf_e_real_direct_threaded_oracle.gd.
The actual direct/threaded N158 benchmark now requires a bounded, exact-checkpoint-gated 100-paid-tick scalar accounting report before publishing each milestone window. It checks every SourceClock and direct/worker timing, computes request minus advance/projection overhead and paired totals, rejects malformed or discontinuous samples, compares nonoverlapping early/late windows, and retains no mutable World/sample references. No changes to A/B/C/D domains or default game path.
Test: p2_perf_e_paid_tick_sample_integrity.gd — positive full window and late comparison; negative SourceClock, request underflow, negative timing, nonexact parity, forged overhead, forged paired totals, forged outcome counts, overlapping windows; detached alias mutation. Not executed, no Actions.
NEXT ASTRA E: bounded direct-vs-threaded benchmark overhead A/B with instrumentation opt-in/off at same seed and exact checkpoint parity; agree A/B interfaces for internal copy/Schema/N9 measurements. Run Windows Godot manually later.
