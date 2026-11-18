# Astra E — authoritative N9 and Source event growth parity
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: E
START: 2026-11-18 17:54 MSK
BASE_SHA: ec345f7b1804803f71317026058b44340ed53f17
ASTRA: E bounded paid-tick early/late benchmarking; N9 receipts and source event size parity at committed checkpoints.
INTENDED_FILES: godot/scripts/sim/phase2/n158_direct_threaded_acceptance.gd; godot/tests/p2_perf_e_real_direct_threaded_oracle.gd; godot/tests/p2_perf_e_n9_events_size_parity.gd
EXPECTED_TEST: positive detached N9/events counts and growth; negative missing/malformed journal, queue, divergent counts, clock, alias.
SAFETY: no World/N9/event mutation; no Actions; no changes to worker/UI.

CODE_SHA: ab6ea23b309b5eb86618d7d9a9475490f6e1092d, 31f7ac200075e00fe3111afecdee26c806a43c00
TEST_SHA: c9da778f088bc92b35418588c22ba37448e15278
TEST: NOT_RUN / CODE_UNVERIFIED / PERFORMANCE_NOT_MEASURED
DONE: Existing real direct/thread checkpoint harness now extracts N9 ledger receipts from native_production.ledger and Source events from top-level events.pending, rejects malformed/missing data and count divergence, reports growth between tick100 and tick300. Reuses already detached authoritative checkpoints; no new World copy or changed simulation logic. Added positive/negative fixture for size drift, missing shapes, wrong SourceClock, malformed entries, alias independence and reversed/forged boundaries.
NEXT ASTRA E: bounded direct/thread late windows at 600/900 with strict budget and snapshot parity; measure worker-vs-direct overhead without treating elapsed wall time as CPU.
