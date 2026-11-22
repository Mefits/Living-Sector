# ASTRA III / E — paid-tick phase + size + parity acceptance bundle

STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: E
START: 2026-11-18 11:50 MSK
BASE HEAD: 8bcae0e3f98701d452d9ac4e67cd18b9aa095c77
CLAIM SHA: 8a51ab6b53cd26c990afc8a40acba24be79d68d2
CODE SHA: 12f7c130d21e3bcbc68f32bbcb689722109d6cf6
TEST SHA: ad01a6b0a33a49a64e16bea080a94493e1a3f35a
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED

ASTRA item: E bounded benchmarking, exact paid-tick windows, direct/worker phase and request attribution, authoritative size counters and exact N38/BT/RNG parity.

FILES:
- godot/scripts/sim/phase2/n158_paid_tick_acceptance.gd
- godot/tests/p2_perf_e_paid_tick_acceptance_bundle.gd

RESULT: capture() requires exactly 100 contiguous paid-tick phase and one-paid-tick request samples with a matching detached completed checkpoint, validated authoritative size counters, and detached copied evidence. compare() refuses unequal source snapshots, N9/BT/RNG/cargo, count mismatches, incomplete coverage, invalid phase distributions and invalid request attribution; returns phase and request wall-time deltas without claiming speedup. Positive and negative/oracle fixtures added. No authoritative runtime or N39/N9/N38/worker/UI source changed. Not yet wired into automated benchmark entrypoint; acceptance harness is callable by the E benchmark runner.

NEXT ASTRA E: wire this capture/compare contract into the existing actual paid-tick benchmark entrypoint (not UI), then execute bounded 100/300/600/900 same-seed direct/worker and N38 restart checks after user permits testing. No Actions now.
