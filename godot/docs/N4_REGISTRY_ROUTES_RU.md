# N4 — Frozen Galaxy 0.6.7 entity registry and route graph

Source: `archive/rust-galaxy-067-reference`, `native/priv/galaxy/data/worlds/*.json`. The Godot P1 model is not replaced; the registry is a data-only `RefCounted` service ready for integration with later fleet/economy phases.

- Native data: **8 systems, 3 factions, 47 bodies, 15 facilities, 24 ships, 3 markets, 3 populations, 9 nav sites and 12 directed route edges**.
- Native ships, populations and nav sites have **no `id`**. The adapter uses `@system-id/source-array-index` as a stable **seed-specific surrogate key**. It is not a native Rust ID. Future mutable ships need a separate persistent runtime ID allocator; never use the array ordinal as a globally durable spawned-ship ID.
- Markets have IDs, but `facility_id` refers to the native station **location**, not always the facility's object ID. Do not conflate them.
- Native `travel_routes[].distance` is the route weight. `system.universe_offset` is an arbitrary map coordinate, not a distance unit in light-years. Graph edges are **directed** as written; reverse edges must not be invented. Cross-system endpoints are preserved.
- Dijkstra returns a deterministic shortest directed path, with lexicographic tie-breaking. No physical ship movement, docking or fuel consumption is simulated by this service.
- Snapshot lists are sorted by stable compound identity and source endpoints. It is a deterministic identity/route export, **not** a full mutable simulation save.
- Registry and graph build into staging dictionaries, committing only after complete validation; invalid distance, duplicate ID and duplicate directed edge reject the input.

Example native route: earth-station → lane-epsilon (115) → lane-tau (150) → lane-barnard (200) → pirate-outpost (390), **total 855 native route-distance units**. The reverse route is not present.

Short Godot acceptance:

```sh
godot --headless --path godot --script res://tests/n4_registry_routes_check.gd
```

At creation, Godot Runtime was unavailable. Static source audit confirms all 8 seed JSON worlds and 12 distinct edges, but Godot syntax/runtime are **CODE_UNVERIFIED**. N4 is not a completed ship navigation or economy system. Future N13/N14 should consume this graph after validating actual movement semantics from Rust.
