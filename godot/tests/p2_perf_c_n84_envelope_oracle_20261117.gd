extends RefCounted
## C regression: cached envelope must match uncached N14 preview for real
## source ships, including a changed token and an unrelated invalid row.
const ShipPhase = preload("res://scripts/sim/phase2/unified_ship_phase.gd")

static func run(world: Dictionary, graph: RefCounted,
        positions: Dictionary, ship_id: String, destination: String,
        tick: int = 1) -> Dictionary:
    var scratch: Dictionary = {}
    var first: Dictionary = ShipPhase.preview_depart(world, graph, positions,
        tick, 1.0, ship_id, destination, scratch)
    var oracle: Dictionary = ShipPhase.preview_depart(world, graph, positions,
        tick, 1.0, ship_id, destination)
    if first != oracle:
        return {"ok": false, "reason": "first_preview_differs"}
    var repeated: Dictionary = ShipPhase.preview_depart(world, graph, positions,
        tick, 1.0, ship_id, destination, scratch)
    if repeated != oracle:
        return {"ok": false, "reason": "cached_preview_differs"}
    var changed: Dictionary = world.duplicate(true)
    changed["ship_next_token"] = int(world["ship_next_token"]) + 1
    var stale: Dictionary = ShipPhase.preview_depart(changed, graph, positions,
        tick, 1.0, ship_id, destination, scratch)
    var stale_oracle: Dictionary = ShipPhase.preview_depart(changed, graph,
        positions, tick, 1.0, ship_id, destination)
    if stale != stale_oracle:
        return {"ok": false, "reason": "token_invalidation_differs"}
    return {"ok": true}
