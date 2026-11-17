extends RefCounted
## N84 Travel preview must preserve the old full-copy oracle and never alias World.
const ShipPhase = preload("res://scripts/sim/phase2/unified_ship_phase.gd")
const ShipState = preload("res://scripts/sim/ship_state.gd")
const Graph = preload("res://scripts/sim/route_graph.gd")

static func run() -> Dictionary:
    var fleet = ShipState.new()
    if not fleet.add_ship("ship_a", "miner", "faction_a", "system_a"):
        return {"ok": false, "reason": "fixture_a"}
    if not fleet.add_ship("ship_b", "miner", "faction_b", "system_a"):
        return {"ok": false, "reason": "fixture_b"}
    fleet.ships["ship_a"]["location"] = "earth"
    fleet.ships["ship_b"]["location"] = "earth"
    fleet.ships["ship_a"]["cargo"] = {"ore": 7}
    fleet.ships["ship_b"]["cargo"] = {"ice": 9}
    var world: Dictionary = {"ships": fleet.ships.duplicate(true), "ship_next_token": 10}
    var original: Dictionary = world.duplicate(true)
    var graph = Graph.new()
    if not graph.load_worlds([{"system": {"id": "system_a"},
            "travel_routes": [{"from": "earth", "to": "mars", "distance": 10.0}],
            "nav_sites": [{"name": "earth"}, {"name": "mars"}]}]):
        return {"ok": false, "reason": "graph_fixture"}
    var positions: Dictionary = {"earth": Vector2.ZERO, "mars": Vector2(10, 0)}
    var preview: Dictionary = ShipPhase.depart(world, graph, positions, 1, 1.0, "ship_a", "mars")
    if not preview.get("ok", false):
        return {"ok": false, "reason": "preview_" + str(preview.get("reason", ""))}
    # Old publication path was a deep copy of the detached ShipState fleet.
    var legacy_oracle: Dictionary = preview["ships"].duplicate(true)
    if preview["ships"] != legacy_oracle or world != original:
        return {"ok": false, "reason": "old_snapshot_or_world_parity"}
    if str(preview["ships"]["ship_a"].get("location", "?")) != "" or (
            str(preview["ships"]["ship_a"]["transit"].get("to", "")) != "mars"):
        return {"ok": false, "reason": "real_departure"}
    if int(preview["ships"]["ship_a"]["transit"].get("token", -1)) != 10 or (
            int(preview.get("next_token", -1)) != 11):
        return {"ok": false, "reason": "token_order"}
    if preview["ships"]["ship_b"] != original["ships"]["ship_b"]:
        return {"ok": false, "reason": "sleeping_ship_changed"}
    preview["ships"]["ship_a"]["cargo"]["ore"] = 99
    preview["ships"]["ship_b"]["cargo"]["ice"] = 99
    preview["ships"]["ship_a"]["transit"]["token"] = 999
    if world != original or int(legacy_oracle["ship_a"]["cargo"]["ore"]) != 7 or (
            int(legacy_oracle["ship_b"]["cargo"]["ice"]) != 9):
        return {"ok": false, "reason": "mutable_alias"}
    # Invalid destination cannot invent a flight or consume cargo/fuel.
    var rejected: Dictionary = ShipPhase.depart(world, graph, positions, 1, 1.0, "ship_a", "unknown")
    if rejected.get("ok", false) or world != original:
        return {"ok": false, "reason": "invalid_route_mutated_world"}
    return {"ok": true}
