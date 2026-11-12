# N59 — Directed multi-hop route planner (CODE_UNVERIFIED)

Source of mechanics: frozen Rust `native/crates/sim_core/src/world/pathfinder.rs` (Dijkstra; travel route weight=distance; gate weight=5, nominal leg distance=1; no-path returns None). Godot planner is opt-in and read-only; no cargo, fuel, credits, docking or live ship mutation. Unlike Rust's legacy `route_actions` direct-travel fallback, unknown/unreachable paths fail closed. Directed topology is preserved; no synthetic reverse edges.

Native Godot: `RefCounted`, `Array`, `Dictionary`, `sort_custom`; binary heap for O((V+E)log V) Dijkstra; stable lexical tie ordering. Alternative AStar2D/AStar3D requires artificial coordinate/point topology and obscures gate-specific action semantics; no plugin installed. For large graphs, benchmark heap allocations and consider packed adjacency representation; thousands of ships should share the graph, not construct one planner per Node.

API: `plan(locations: Array, routes: Array, gate_pairs: Dictionary, origin: String, destination: String) -> Dictionary`; routes are directed `{from,to,distance}`; gate map is symmetric. Result `{ok, legs, cost}`; legs carry `{from,to,distance,kind}`, `kind` travel/gate. Input is fully validated before search. Tie-breaking deterministic but may differ from Rust's unspecified BinaryHeap tie ordering; cost and validity should match.

Static review: Rust formula and gate weight inspected, no Rust compilation. Headless test prepared (not executed):
`godot --headless --path godot --script res://tests/n59_directed_route_planner_check.gd`.
No Godot executable in this run. No claim of RUNTIME_MECHANICS_VERIFIED. Future: adapt validated native route registry and gate facility pairing; execute each leg through authoritative ship/docking/gate-payment phases, never auto-teleport.
