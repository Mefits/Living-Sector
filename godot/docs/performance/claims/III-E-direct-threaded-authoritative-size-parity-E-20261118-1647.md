# Astra E — direct/thread detached N39 size parity
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: E
START: 2026-11-18 16:47 Europe/Moscow
BASE_SHA: d10b1e58d50fd7247834ab27532ade8e907b549f
ASTRA: E bounded paid-tick profiling and same-seed early/late size/parity, 100/300 checkpoints; not worker/UI.
SCOPE: Integrate authoritative detached N39 size counters into existing real direct/thread oracle and verify exact per-category equality and early/late deltas without inventing N9/event counts.
INTENDED FILES: godot/scripts/sim/phase2/n158_direct_threaded_acceptance.gd; godot/tests/p2_perf_e_real_direct_threaded_oracle.gd; godot/tests/p2_perf_e_direct_threaded_size_parity.gd.
TEST: positive identical checkpoint size counts, negative mismatched receipts/contracts/dock/ships, malformed/missing domain and source tick; no Actions.
RISK: all counters read detached checkpoint only, no mutation or alias; source parity remains exact.

END: 2026-11-18 Europe/Moscow
CODE_SHA: 89b5cc42c1231c85048c24b6366d8e73c54683da; 7ecde99f7bc8e0893bb81a7ad9349a80e218e970
TEST_SHA: bb38f2a4d23316559e18dce34d97332c95b20f57
TEST: NOT_RUN / CODE_UNVERIFIED / PERFORMANCE_NOT_MEASURED
RESULT: n158_direct_threaded_acceptance.gd compares detached authoritative World sizes by ship, facility, dock waiting, contract and individual receipt categories at paid tick 100/300; rejects malformed/missing domains and wrong source clock. Existing real same-seed direct/thread oracle now invokes it at exact checkpoint boundaries and emits early-to-late count deltas, without creating fake N9/event counts or touching World ownership. Regression covers parity, mismatches, malformed dock, missing world, invalid clock, receipt coverage, deep-copy detachment and growth.
NEXT ASTRA E: capture separately authoritative N9 receipts and Source event counts for both direct/thread owners at paid boundaries (without World inference), then 600/900 bounded late parity under the existing wall budget.
