# II-C N153 route geometry preflight
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: C
TIME: 2026-11-18 21:33 MSK
BASE SHA: 56b8eee37602f395762ebc64fea9218ca576c517
ASTRA: II-C ship/contract/dock/route caches, stable tie-break, proposal-local invalidation.

CODE SHA: 152141510d0d1a279b7f6c2ed67996c20f5ef8e9, d015f7faa8b3a0afb3963925ffc49129f9f077a4
TEST SHA: 885dc7878a2d599abe4f6b212b174255ec8363c1
FILES:
- godot/scripts/sim/phase2/n153_ship_eligibility_index.gd
- godot/scripts/sim/phase2/unified_n153_contract_dispatch.gd
- godot/tests/p2_perf_c_n153_route_geometry_preflight.gd

IMPLEMENTATION: N153 now shares inbound N4 shortest paths, endpoint presence and scalar inbound geometry across posted offers with same source and different destinations. Existing source/destination/here per-offer route index remains intact. Shared root is allocated anew for every synchronous propose(), never persists to next tick, World mutation or N38 restore. Public legs() still detaches arrays and scalar rows. No change to N153 profit, cargo, fuel, BT, payment, ship assignment, route tie-break or outbound lookup order.

TEST: NOT_RUN / CODE_UNVERIFIED / PERFORMANCE_NOT_MEASURED.
TARGETED ORACLE: cached vs uncached on multiple directed destinations, missing endpoints, unreachable routes, caller mutation, changed positions between proposals and graph replacement. Test requires Godot runtime; no GitHub Actions triggered.
RISK: Full paid economy same-seed parity and performance not measured; verify source and destination bid choices, exact fuel/BT and N38 restart on Windows before accepting.

NEXT ASTRA II-C: profile and optimize remaining N84/N153 paid-tick ship candidate scans and dock occupancy, with 24/100/500 actual paid ship fixtures and negative cargo/contract/BT oracle.
