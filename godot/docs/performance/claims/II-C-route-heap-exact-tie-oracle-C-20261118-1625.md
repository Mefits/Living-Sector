# II-C — N4 route frontier exact tie parity and stale cache
STATUS: IN_PROGRESS
OWNER: C
START: 2026-11-18 16:25 MSK
BASE_SHA: 8c4c55048e14127be1d116acda83c504ada23643
ASTRA: II-C ship/route graph repeated contract hotpath, deterministic route/tie-break, cache invalidation
INTENDED FILES: godot/scripts/sim/route_graph.gd; godot/tests/p2_perf_c_route_heap_exact_oracle.gd
CHECK: legacy linear Dijkstra independent oracle, near-equal ties, stale cache after load, directed/unknown, returned alias.
RISK: approximate distance comparator is nontransitive; preserve source algorithm exact selection semantics.
