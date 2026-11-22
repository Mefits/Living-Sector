# II-C N153 bidder context allocation / callsites
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: C
START: 2026-11-19 07:30 MSK
BASE SHA: 926f53545a5cfd8c05cea7a1e9fe03195aca7ce5
ASTRA: II-C fleet/contracts — reduce repeated C×S per-offer DTO work, preserve source N153 decision, stable tie-break, cargo/payment/route gates.
INTENDED FILES: godot/scripts/sim/phase2/unified_n153_contract_dispatch.gd; godot/tests/p2_perf_c_n153_bid_context_owned_roster.gd
EXPECTED: proposal-local immutable offer/system/commercial contexts, no cross-bid mutable aliases, old/new oracle positive and negatives (same faction, distinct seller/buyer, missing system, changed offer, tie-break).
CODE SHA: 105534bc66be18b2550db20bc23ffd625857291d
TEST SHA: a436cfba82ce77f7ab28fe3625b72585cdc92c8a
TEST: NOT_RUN / CODE_UNVERIFIED / PERFORMANCE_NOT_MEASURED
RESULT: N153 reuses one per-offer commerce view per ship faction and immutable offer array; bid-specific context, quotes, memory wrappers remain distinct. Exact N153 selector is unchanged. Targeted oracle compares old and new contexts across factions/payment, invalid funding, alias and new-proposal invalidation.
RISK: Godot parser and paid-tick parity unverified; no measured speedup.
NEXT ASTRA II-C: N84/N153 dock occupancy and paid 24/100/500 fleet BT/cargo/fuel/route parity; avoid N140 no-AgentLod and transferred #275.
