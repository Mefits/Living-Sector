# II-C N153 bidder context allocation / callsites
STATUS: IN_PROGRESS
OWNER: C
START: 2026-11-19 07:30 MSK
BASE SHA: 926f53545a5cfd8c05cea7a1e9fe03195aca7ce5
ASTRA: II-C fleet/contracts — reduce repeated C×S per-offer DTO work, preserve source N153 decision, stable tie-break, cargo/payment/route gates.
INTENDED FILES: godot/scripts/sim/phase2/unified_n153_contract_dispatch.gd; godot/tests/p2_perf_c_n153_bid_context_owned_roster.gd
EXPECTED: proposal-local immutable offer/system/commercial contexts, no cross-bid mutable aliases, old/new oracle positive and negatives (same faction, distinct seller/buyer, missing system, changed offer, tie-break).
TEST: NOT_RUN
