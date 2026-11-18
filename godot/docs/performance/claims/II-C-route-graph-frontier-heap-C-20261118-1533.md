# II-C — route graph frontier complexity
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: C
START: 2026-11-18 15:33 Europe/Moscow
BASE_SHA: 8e6a34e5fc5f45dd3c52553539c43c2696b45ae6
ASTRA: II-C ship/route paid-tick hotpaths; repeated N153 directed shortest-path queries.
FILES: godot/scripts/sim/route_graph.gd; godot/tests/p2_perf_c_route_heap_oracle.gd
GOAL: replace quadratic unsettled-node scan with deterministic indexed frontier; preserve approximate float tie-break, directed routes, negative routes, cache invalidation and detached ownership. Test cached/uncached against independent oracle including equal-cost ties, graph reload, bad graph and caller mutation.
CODE_SHA: 3a743673444888f659591e3b3c4b7a198f19102d; comparator correction 5cc48b1bf760955b6da80198408d2f4835014235
TEST_SHA: 5dfec93c559e4e96ed155882618a265cc4ffcc5f
TEST: NOT_RUN / CODE_UNVERIFIED / PERFORMANCE_NOT_MEASURED
DONE: replaced per-node scan of all tentative routes in N4 directed Dijkstra with lazy binary heap, including stale-entry rejection, path updates, and existing bounded detached route cache. Added independent original O(V²) oracle for directed, equal-distance, dense graphs, reload, invalid reload, negative routes, caller mutation.
RISK: Approximate float tie comparison is not a strict total ordering; heap may differ from original linear scan for near-equal distances. Do not accept without executing oracle and same-seed replay; revert if exact parity differs.
NEXT: II-C N153 contract/route invalidation and same-seed 24/100/500 fleet paid tick tests with fuel/cargo/BT tie negatives.
