# II-C N153 offer-context paid dispatch
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: C
TIME: 2026-11-18 13:34 MSK
BASE_SHA: c1aa68545e4f51ac87482772dbcadd6d4b04f519
ASTRA: II-C ship/contract/dock/route caches — N153 repeated per-offer funding/observations
CODE_SHA: a968c564fb5e19f3ee8b735800285c3991b56a6c
TEST_SHA: 9d77ce729c4ce51375c87b6379efc65724375614
FILES:
- godot/scripts/sim/phase2/unified_n153_contract_dispatch.gd
- godot/tests/p2_perf_c_n153_offer_context.gd
IMPLEMENTED:
- Resolve N154 payer identity, account ownership, and balance once per posted offer, not per candidate ship. Per-ship comms bonus, top-up and actual quote validity remain per bid.
- Cache offer source/destination system lookups after first ready ship while retaining per-ship origin and original resolver ordering.
- Reuse offer commerce baseline with detached per-bid dictionary; keep native selector and winner tie-break, fuel, cargo, BT planning unchanged.
TEST: NOT_RUN
CODE_UNVERIFIED: true
PERFORMANCE_NOT_MEASURED: true
ORACLE: legacy per-bid payer calculation, faction/facility/HTN/invalid ownership, treasury mutation between proposals, missing contract authorization, quote top-up boundaries, commerce isolation.
RISKS: Godot runtime and full N153 same-seed replay not run; source resolver mutation side effects assumed absent (read-only resolver).
NEXT: II-C N153 contract eligibility/route index invalidation and source-level paid dispatch profiling; exact selector/BT/cargo parity with 24/100/500 ship fixtures.
