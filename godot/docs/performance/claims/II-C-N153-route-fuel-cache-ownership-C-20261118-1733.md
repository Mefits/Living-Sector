# II-C — N153 route/fuel cache ownership and invalidation
STATUS: IN_PROGRESS
OWNER: C
START: 2026-11-18 17:33 MSK
BASE SHA: c2ccf822e9ef2af192cbdccc841d4aae2160f40d
ASTRA: C — Fleet, contracts, route graph, hot ship indices: indexed eligible ships & available contracts, versioned graph routes, stable tie-break, invalidation on ship/contract changes.
INTENDED FILES: godot/scripts/sim/phase2/unified_n153_contract_dispatch.gd; godot/scripts/sim/phase2/n153_ship_eligibility_index.gd; godot/tests/p2_perf_c_n153_route_fuel_cache_ownership.gd
CHECK: independent cached/uncached route fuel and stale ownership/position/fuel negatives, deterministic contract order.
