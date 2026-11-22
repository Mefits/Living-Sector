# II-C — N4 route frontier exact tie parity and stale cache
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: C
START: 2026-11-18 16:25 MSK
BASE_SHA: 8c4c55048e14127be1d116acda83c504ada23643
ASTRA: II-C ship/route graph repeated contract hotpath, deterministic route/tie-break, cache invalidation
INTENDED FILES: godot/scripts/sim/route_graph.gd; godot/tests/p2_perf_c_route_heap_exact_oracle.gd
CHECK: legacy linear Dijkstra independent oracle, near-equal ties, stale cache after load, directed/unknown, returned alias.
RISK: approximate distance comparator is nontransitive; preserve source algorithm exact selection semantics.

CODE_SHA: 749328940678057d2c139d2531493504f552c79e, fa0eac16a010893f2e0a0e1f3871b7bde04eb640
TEST_SHA: faaf1393a1daf6645afc8e56400600c2b7089544
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED
RESULT: route_graph.gd now uses a strict total order for heap entries and falls back to the original source linear Dijkstra when distinct near-equal frontier costs make approximate ordering nontransitive. This preserves the original path and tie selection in ambiguous cases while retaining the heap for ordinary exact-cost frontiers. The same cached shortest_path callsite and load_worlds invalidation remain authoritative. Test compares the independent existing linear oracle on directed near-equal and dense graphs, mutable result alias, failed reload, and successful reload.
RISK: The fallback is conservative and still requires Godot runtime verification; source legacy scan is O(V²) when triggered. Exact same-seed route/contract/BT/cargo parity is pending.
NEXT: II-C N153 contract candidate route/eligibility index invalidation with paid cargo/fuel/ownership negatives; same-seed paid-tick profile 100/600/900 after manual acceptance.
