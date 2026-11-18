# II-C — route graph frontier complexity
STATUS: IN_PROGRESS
OWNER: C
START: 2026-11-18 15:33 Europe/Moscow
BASE_SHA: 8e6a34e5fc5f45dd3c52553539c43c2696b45ae6
ASTRA: II-C ship/route paid-tick hotpaths; repeated N153 directed shortest-path queries.
FILES: godot/scripts/sim/route_graph.gd; godot/tests/p2_perf_c_route_heap_oracle.gd
GOAL: replace quadratic unsettled-node scan with deterministic indexed frontier; preserve approximate float tie-break, directed routes, negative routes, cache invalidation and detached ownership. Test cached/uncached against independent oracle including equal-cost ties, graph reload, bad graph and caller mutation.
TEST: NOT_RUN
