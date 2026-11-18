# Astra E — direct/thread detached N39 size parity
STATUS: IN_PROGRESS
OWNER: E
START: 2026-11-18 16:47 Europe/Moscow
BASE_SHA: d10b1e58d50fd7247834ab27532ade8e907b549f
ASTRA: E bounded paid-tick profiling and same-seed early/late size/parity, 100/300 checkpoints; not worker/UI.
SCOPE: Integrate authoritative detached N39 size counters into existing real direct/thread oracle and verify exact per-category equality and early/late deltas without inventing N9/event counts.
INTENDED FILES: godot/scripts/sim/phase2/n158_direct_threaded_acceptance.gd; godot/tests/p2_perf_e_real_direct_threaded_oracle.gd; godot/tests/p2_perf_e_direct_threaded_size_parity.gd.
TEST: positive identical checkpoint size counts, negative mismatched receipts/contracts/dock/ships, malformed/missing domain and source tick; no Actions.
RISK: all counters read detached checkpoint only, no mutation or alias; source parity remains exact.
