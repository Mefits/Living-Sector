# Astra E — authoritative N9 and Source event growth parity
STATUS: IN_PROGRESS
OWNER: E
START: 2026-11-18 17:54 MSK
BASE_SHA: ec345f7b1804803f71317026058b44340ed53f17
ASTRA: E bounded paid-tick early/late benchmarking; N9 receipts and source event size parity at committed checkpoints.
INTENDED_FILES: godot/scripts/sim/phase2/n158_direct_threaded_acceptance.gd; godot/tests/p2_perf_e_real_direct_threaded_oracle.gd; godot/tests/p2_perf_e_n9_events_size_parity.gd
EXPECTED_TEST: positive detached N9/events counts and growth; negative missing/malformed journal, queue, divergent counts, clock, alias.
SAFETY: no World/N9/event mutation; no Actions; no changes to worker/UI.
