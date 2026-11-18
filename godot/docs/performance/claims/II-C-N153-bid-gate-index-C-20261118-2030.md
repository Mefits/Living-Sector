# II-C — N153 proposal-local bidder gate index
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: C
DATE: 2026-11-18 20:30 MSK
BASE_SHA: 2878d1c38967e8d8ef9446f08842d2cf6127278c
ASTRA: II-C ship/contract/dock/route caches; indexed eligible ships & available contracts with deterministic invalidation and exact rejection/tie-break parity.
SCOPE: N153 repeated per-offer ship faction, outlaw and reputation posture gates; preserve per-offer blocker counts and per-ship bid order.
INTENDED_FILES: godot/scripts/sim/phase2/unified_n153_contract_dispatch.gd; godot/tests/p2_perf_c_n153_bid_gate_index.gd
EXPECTED_TEST: cached-vs-uncached independent oracle across multiple offers, missing faction, outlaw, reputation, assignment, mutation between calls, equal profit and source rejection ordering.
RISKS: no persistent cache, no skipped native N153/BT decisions, no changed blocker counts.

## Implemented
CODE_SHA: 15856741fa82c244b145a504dd5470ca3ddbef11
TEST_SHA: 2455d7670789f0db9d0104a74d97317261837260
FILES: godot/scripts/sim/phase2/unified_n153_contract_dispatch.gd; godot/tests/p2_perf_c_n153_bid_gate_index.gd
CODE: proposal-local sorted bidder roster and seller/buyer/ship reputation gate cache; preserve per-offer assignment priority, blocker counts, seller-specific posture, native selector/BT and quote calls; avoid per-bid systems.values() array allocation. No persistent index or World mutation.
TEST: NOT_RUN / CODE_UNVERIFIED / PERFORMANCE_NOT_MEASURED. Independent old-gate oracle checks 240 ships, 18 offers, missing faction, outlaw, reputation, assigned winner, reason counts, changed factions/reputation across proposals and input ownership. No Godot execution or same-seed parity yet.
NEXT_ASTRA: II-C N84/N153 remaining fleet and contract hot loops; compare 24/100/500 real paid contract fixtures and exact BT/cargo/route/fuel outcomes, check N4 cached-vs-uncached route oracle before accepting speedups.
