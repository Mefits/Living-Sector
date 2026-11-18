# II-C — N153 route/fuel cache ownership and invalidation
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: C
START: 2026-11-18 17:33 MSK
BASE SHA: c2ccf822e9ef2af192cbdccc841d4aae2160f40d
ASTRA: C — Fleet, contracts, route graph, hot ship indices: indexed eligible ships & available contracts, versioned graph routes, stable tie-break, invalidation on ship/contract changes.
INTENDED FILES: godot/scripts/sim/phase2/unified_n153_contract_dispatch.gd; godot/scripts/sim/phase2/n153_ship_eligibility_index.gd; godot/tests/p2_perf_c_n153_route_fuel_cache_ownership.gd
CHECK: independent cached/uncached route fuel and stale ownership/position/fuel negatives, deterministic contract order.

CODE SHA: 55cdede71fcf1e0868d4d0dba223d0401ee27fcd; bea33fcc62fbe12918a1af16184e4ac8d320dcf0
TEST SHA: 1236157051791cdc790a40748d187fdd0c124376
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED.
CHANGES: n153_ship_eligibility_index.legs reuses proposal-private immutable outbound rows; external detach still clones all rows. unified_n153_contract_dispatch._ready_ship caches per-origin/speed/scale edge tick counts independently of per-rate floating fuel sums, preserving per-edge order, fuel/contract gating and proposal-scoped invalidation.
NEGATIVES: cargo nonempty, insufficient fuel, caller mutation, graph reload/position change with fresh cache; 24 distinct ships and independent edge-by-edge oracle.
NEXT ASTRA C: indexed available-contract/eligible-ship roster with deterministic invalidation on ownership/dock/contract changes, and exact BT/order parity at paid tick checkpoints.
