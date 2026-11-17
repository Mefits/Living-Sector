# PERF C handoff — 2026-11-17 N153 bidder geometry

CODE: 150ef48ca307dedf101612bbc7b0a0189a5e53fd, 8f53e62204aa294de2aa387c63308219c3239500
TEST: 21f80eab3ec063d9d591842a1c814d102974a1e9
FILES: phase2/n153_ship_eligibility_index.gd; phase2/unified_n153_contract_dispatch.gd; tests/p2_perf_c_n153_readonly_legs_oracle_20261117.gd

Actual hotpath: N153 _ready_ship() asks EligibilityIndex.legs() for each bidder. Previously even cache hits detached every geometry step Dictionary and path arrays for each bidder. N153 only reads steps; it now requests a proposal-local read-only view, and duplicates only inbound/outbound arrays on successful readiness before they escape into candidate rows. The default public legs() remains detached for other callers. No persistent cache, no World mutations, no altered eligibility, fuel, paid-contract gates or winner ordering.

TEST EXECUTED: NOT RUN; CODE_UNVERIFIED. GitHub source edits committed; Godot runtime and same-seed profiling not executed. Existing 500-tick CI predates this patch. Performance benefit unmeasured. Test compares cached read-only geometry to original detached oracle, verifies default detachment, stale position invalidation across proposals, and reverse directed route behavior. Need targeted parser/test and exact N9/N39/N38/BT/RNG/contract/cargo replay before acceptance.

NEXT: E to collect source-level N153 calls, geometry row-copy time, ships+dock paid-tick avg/p95 at 100/600/900 same seed; C to tackle next measured dominant site rather than speculative index. No CI launched per single commit.
