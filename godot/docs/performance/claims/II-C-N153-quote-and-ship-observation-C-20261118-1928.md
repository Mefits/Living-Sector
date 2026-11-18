# II-C N153 repeated bid observations
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: C
TIME: 2026-11-18 19:28 MSK
BASE_SHA: c20164c2ab9b508913bcd0789cac48b4469c3ab8
ASTRA: II-C ship/contract/dock/route caches — N153 repeated per-bid quote and sensor/comms observations
INTENDED_FILES: godot/scripts/sim/phase2/unified_n153_contract_dispatch.gd; godot/tests/p2_perf_c_n153_bid_observation_oracle.gd
CHECK: cached vs uncached quote, sensor and bonus gates; changed source price/ship/contract between proposals; source order, BT, cargo, funding, tie-break.

CODE_SHA: 0c6f976556adecd41b67d7626733ff2642e41448; 0a48b6e01ebdcaff08d8d3cdbe430685ee5726d5
TEST_SHA: 8b9663410cce60bef9123d5031a6dfcc36081b56
TEST: NOT_RUN
PERFORMANCE: NOT_MEASURED
IMPLEMENTED: N153.propose now shares per-offer source-purchase quote for identical posture multipliers and proposal-local ship sensor/comms observations; no persistent index, no mutable World alias. Offer funding, route/fuel, N153 selector and N81 BT gates remain per-bid; original rejection order and profit tie-break retained.
NEGATIVES: zero/invalid/huge quote, different offer price, invalid sensor, huge/small fallback, changed ship observations after scope reset, independent input ship.
RISK: full same-seed paid tick N9/N39/BT/cargo/contract parity and performance require later Godot execution.
NEXT ASTRA II-C: remaining N153 candidate traversal and route invalidation across contracts; measure 24/100/500 active ships, paid ticks 100/600/900.
