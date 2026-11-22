extends RefCounted
## C: the N84 proposal must preserve previously staged BT rows when a
## later ship requests transit. The independent N14 full-fleet oracle
## validates the receipt and unrelated fleet state.
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
    var graph = Graph.new()
    if not graph.load_worlds([{"system": {"id": "system_a"},
            "travel_routes": [{"from": "earth", "to": "mars", "distance": 10.0}],
            "nav_sites": [{"name": "earth"}, {"name": "mars"}]}]):
        return {"ok": false, "reason": "graph"}
    var positions: Dictionary = {"earth": Vector2.ZERO, "mars": Vector2(10, 0)}
    var staged: Dictionary = world.duplicate()
    staged["ships"] = world["ships"].duplicate(true)
    staged["ships"]["ship_001"]["planning_source"] = "earlier_bt_cursor"
    var source_before: Dictionary = world.duplicate(true)
    var full: Dictionary = ShipPhase.depart(staged, graph, positions,
        1, 1.0, "ship_050", "mars")
    var preview: Dictionary = ShipPhase.preview_depart(staged, graph, positions,
        1, 1.0, "ship_050", "mars")
    if not full.get("ok", false) or not preview.get("ok", false):
        return {"ok": false, "reason": "departure"}
    staged["ships"]["ship_050"] = preview["ships"]["ship_050"]
    staged["ship_next_token"] = int(preview["next_token"])
    if staged["ships"] != full["ships"] or staged["ship_next_token"] != full["next_token"]:
        return {"ok": false, "reason": "full_fleet_oracle"}
    if staged["ships"]["ship_001"].get("planning_source", "") != "earlier_bt_cursor":
        return {"ok": false, "reason": "earlier_cursor_lost"}
    if world != source_before:
        return {"ok": false, "reason": "world_mutated"}
    staged["ships"]["ship_050"]["cargo"]["ore"] = -99
    if world != source_before or full["ships"]["ship_050"]["cargo"]["ore"] == -99:
        return {"ok": false, "reason": "mutable_alias"}
    for destination in ["unknown", "earth"]:
        var old: Dictionary = ShipPhase.depart(world, graph, positions,
            1, 1.0, "ship_050", destination)
        var new: Dictionary = ShipPhase.preview_depart(world, graph, positions,
            1, 1.0, "ship_050", destination)
        if old.get("ok", false) != new.get("ok", false) or old.get("reason", "") != new.get("reason", ""):
            return {"ok": false, "reason": "negative_route"}
    return {"ok": true}
