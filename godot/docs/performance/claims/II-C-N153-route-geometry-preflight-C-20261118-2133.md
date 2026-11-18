# II-C N153 route geometry preflight
STATUS: IN_PROGRESS
OWNER: C
TIME: 2026-11-18 21:33 MSK
BASE SHA: 56b8eee37602f395762ebc64fea9218ca576c517
ASTRA: II-C ship/contract/dock/route caches; indexed eligible ships and available contracts, stable tie-break, deterministic invalidation.
SCOPE: godot/scripts/sim/phase2/n153_ship_eligibility_index.gd; godot/scripts/sim/phase2/unified_n153_contract_dispatch.gd; godot/tests/p2_perf_c_n153_route_geometry_preflight.gd
GOAL: reduce repeated graph route/position preflight for multi-offer, multi-ship dispatch while preserving exact route/BT/cargo/fuel and rejection ordering; positive and negative uncached oracle.
TEST: NOT_RUN; CODE_UNVERIFIED.
