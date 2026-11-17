extends RefCounted
## N84 single-ship preview against the authoritative full-fleet N14 oracle.
const ShipPhase = preload("res://scripts/sim/phase2/unified_ship_phase.gd")
const ShipState = preload("res://scripts/sim/ship_state.gd")
const Graph = preload("res://scripts/sim/route_graph.gd")

static func run() -> Dictionary:
    var fleet = ShipState.new()
    for n in range(100):
        var id: String = "ship_%03d" % n
        if not fleet.add_ship(id, "miner", "faction_%d" % n, "system_a"):
            return {"ok": false, "reason": "fixture"}
        fleet.ships[id]["location"] = "earth"
        fleet.ships[id]["cargo"] = {"ore": n}
    var world: Dictionary = {"ships": fleet.ships.duplicate(true), "ship_next_token": 123}
    var before: Dictionary = world.duplicate(true)
    var graph = Graph.new()
    if not graph.load_worlds([{"system": {"id": "system_a"},
            "travel_routes": [{"from": "earth", "to": "mars", "distance": 10.0}],
            "nav_sites": [{"name": "earth"}, {"name": "mars"}]}]):
        return {"ok": false, "reason": "graph"}
    var positions: Dictionary = {"earth": Vector2.ZERO, "mars": Vector2(10, 0)}
    var id: String = "ship_050"
    var full: Dictionary = ShipPhase.depart(world, graph, positions, 1, 1.0, id, "mars")
    var fast: Dictionary = ShipPhase.preview_depart(world, graph, positions, 1, 1.0, id, "mars")
    if not full.get("ok", false) or not fast.get("ok", false):
        return {"ok": false, "reason": "valid_departure"}
    if fast["ships"][id] != full["ships"][id] or fast["next_token"] != full["next_token"] or fast["outcomes"] != full["outcomes"]:
        return {"ok": false, "reason": "receipt_oracle"}
    if fast["ships"].size() != 1 or world != before:
        return {"ok": false, "reason": "single_owned_ship"}
    fast["ships"][id]["cargo"]["ore"] = 999
    fast["ships"][id]["transit"]["token"] = 999
    if world != before or full["ships"][id] != ShipPhase.depart(world, graph, positions, 1, 1.0, id, "mars")["ships"][id]:
        return {"ok": false, "reason": "mutable_alias"}
    for destination in ["unknown", "earth"]:
        var rejected: Dictionary = ShipPhase.preview_depart(world, graph, positions, 1, 1.0, id, destination)
        var oracle: Dictionary = ShipPhase.depart(world, graph, positions, 1, 1.0, id, destination)
        if rejected.get("ok", false) != oracle.get("ok", false) or rejected.get("reason", "") != oracle.get("reason", ""):
            return {"ok": false, "reason": "negative_route_oracle"}
    world["ships"][id]["docked_at"] = "dock"
    if ShipPhase.preview_depart(world, graph, positions, 1, 1.0, id, "mars").get("ok", false):
        return {"ok": false, "reason": "occupied_dock"}
    world = before.duplicate(true)
    world["ship_next_token"] = 0
    if ShipPhase.preview_depart(world, graph, positions, 1, 1.0, id, "mars").get("ok", false):
        return {"ok": false, "reason": "stale_token"}
    return {"ok": true}
