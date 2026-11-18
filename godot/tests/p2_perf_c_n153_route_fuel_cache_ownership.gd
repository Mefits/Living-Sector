extends SceneTree
## Proposal-local N153 cache must match independent edge-by-edge fuel oracle.
const Dispatch = preload("res://scripts/sim/phase2/unified_n153_contract_dispatch.gd")
const Eligibility = preload("res://scripts/sim/phase2/n153_ship_eligibility_index.gd")
const RouteGraph = preload("res://scripts/sim/route_graph.gd")
const Transit = preload("res://scripts/sim/ship_transit.gd")

func _oracle(steps: Array, speed: float, rate: float, scale: float) -> float:
    var cost: float = 0.0
    for leg in steps:
        assert(bool(leg["present"]))
        var distance: float = float(leg["distance"])
        var velocity: float = Transit.BASE_VELOCITY * speed * scale
        cost += float(maxi(1, ceili(distance / velocity))) * rate * scale
    return cost

func _initialize() -> void:
    var graph = RouteGraph.new()
    var worlds: Array = [{"system": {"id": "sys"}, "travel_routes": [
        {"from": "A", "to": "B", "distance": 2.0},
        {"from": "B", "to": "C", "distance": 3.0},
        {"from": "C", "to": "D", "distance": 4.0}]}]
    assert(graph.load_worlds(worlds))
    var positions: Dictionary = {"A": Vector2(0, 0), "B": Vector2(15, 0),
        "C": Vector2(15, 30), "D": Vector2(60, 30)}
    var world: Dictionary = {"facilities": {}, "ships": {}}
    var offer: Dictionary = {"source_location": "B", "destination_location": "D", "quantity": 10}
    for i in range(24):
        var id: String = "ship_%02d" % i
        world["ships"][id] = {"location": "A" if i % 2 == 0 else "B",
            "cargo": {}, "cargo_capacity": 50, "transit": {}, "active_contract_id": "",
            "docked_at": "", "class": "courier" if i % 3 == 0 else "freighter",
            "size": "small" if i % 3 == 0 else "medium",
            "speed_modifier": 1.5 if i % 3 == 0 else 1.0,
            "fuel": 100000.0}
    var route_cache: Dictionary = {}
    var readiness: Dictionary = {}
    var fitting: Dictionary = {}
    for id in world["ships"]:
        var ship: Dictionary = world["ships"][id]
        var actual: Dictionary = Dispatch._ready_ship(world, id, offer, graph, positions,
            graph, 1.0, route_cache, readiness, fitting)
        assert(actual.get("ok", false))
        var isolated: Dictionary = Eligibility.legs({}, str(ship["location"]), "B", "D",
            graph, positions)
        var rate: float = 0.03 if str(ship["class"]) == "courier" else 0.05
        var cost: float = _oracle(isolated["steps"], float(ship["speed_modifier"]), rate, 1.0)
        ship["fuel"] = cost - 1.0
        var rejected: Dictionary = Dispatch._ready_ship(world, id, offer, graph, positions,
            graph, 1.0, route_cache, readiness, fitting)
        assert(not rejected.get("ok", true))
        assert(rejected.get("reason") == "insufficient_native_full_route_fuel")
        ship["fuel"] = cost + 1.0
        assert(Dispatch._ready_ship(world, id, offer, graph, positions,
            graph, 1.0, route_cache, readiness, fitting).get("ok", false))
    # Caller detachment must protect shared outbound geometry.
    var owned: Dictionary = Eligibility.legs(route_cache, "A", "B", "D", graph, positions)
    var reference: Dictionary = Eligibility.legs(route_cache, "A", "B", "D", graph, positions)
    owned["steps"][0]["distance"] = -1000.0
    owned["outbound"].clear()
    assert(Eligibility.legs(route_cache, "A", "B", "D", graph, positions) == reference)
    # No cross-tick/cross-world cache: new graph and positions use new root.
    worlds[0]["travel_routes"][1]["distance"] = 12.0
    assert(graph.load_worlds(worlds))
    positions["C"] = Vector2(100, 30)
    var fresh: Dictionary = Eligibility.legs({}, "A", "B", "D", graph, positions)
    assert(fresh["steps"] != reference["steps"])
    # Negative stale route and cargo gate, without bypassing N14.
    world["ships"]["ship_00"]["cargo"] = {"ore": 1}
    assert(Dispatch._ready_ship(world, "ship_00", offer, graph, positions,
        graph, 1.0, {}, {}, {}).get("reason") == "ship_cargo_not_empty")
    print("P2_PERF_C_N153_ROUTE_FUEL_CACHE_OWNERSHIP_PASS")
    quit(0)
