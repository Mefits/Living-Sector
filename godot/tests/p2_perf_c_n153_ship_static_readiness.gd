extends SceneTree
## Proposal-local N153 ship readiness and fitting versus independent legacy gates.
## Run: godot --headless --path godot --script res://tests/p2_perf_c_n153_ship_static_readiness.gd
const Dispatch = preload("res://scripts/sim/phase2/unified_n153_contract_dispatch.gd")
const Catalog = preload("res://scripts/sim/ship_catalog.gd")

func _oracle(world: Dictionary, id: String, quantity: int) -> Dictionary:
    var ship: Dictionary = world["ships"][id]
    if str(ship.get("active_contract_id", "")) != "" or not (ship.get("transit", {}) as Dictionary).is_empty():
        return {"ok": false, "reason": "ship_busy"}
    if str(ship.get("location", "")).is_empty():
        return {"ok": false, "reason": "ship_not_at_real_location"}
    var dock: String = str(ship.get("docked_at", ""))
    if not dock.is_empty():
        if not world["facilities"].has(dock) or str(world["facilities"][dock].get("location", "")) != str(ship["location"]):
            return {"ok": false, "reason": "invalid_idle_dock"}
    if not (ship.get("cargo") is Dictionary) or not ship["cargo"].is_empty():
        return {"ok": false, "reason": "ship_cargo_not_empty"}
    if quantity < 1 or int(ship.get("cargo_capacity", 0)) < quantity:
        return {"ok": false, "reason": "cargo_capacity"}
    return {"ok": true}

func _cached(world: Dictionary, id: String, quantity: int, cache: Dictionary) -> Dictionary:
    var base: Dictionary = Dispatch._ship_static_readiness(world, id, cache)
    if not base.get("ok", false):
        return base
    if quantity < 1 or int(world["ships"][id].get("cargo_capacity", 0)) < quantity:
        return {"ok": false, "reason": "cargo_capacity"}
    return {"ok": true}

func _initialize() -> void:
    var world: Dictionary = {"facilities": {"dock": {"location": "A"}}, "ships": {}}
    var ids: Array = []
    for i in range(100):
        var id: String = "ship_%03d" % i
        ids.append(id)
        world["ships"][id] = {
            "location": "A", "docked_at": "dock", "active_contract_id": "",
            "transit": {}, "cargo": {}, "cargo_capacity": 10 + i,
            "class": "freighter", "size": "small", "speed_modifier": 1.25
        }
    # Each rejection must retain its original priority and exact reason.
    world["ships"][ids[1]]["active_contract_id"] = "paid"
    world["ships"][ids[2]]["transit"] = {"to": "B"}
    world["ships"][ids[3]]["location"] = ""
    world["ships"][ids[4]]["docked_at"] = "gone"
    world["ships"][ids[5]]["location"] = "B"
    world["ships"][ids[6]]["cargo"] = {"ore": 1}
    world["ships"][ids[7]]["cargo"] = []
    world["ships"][ids[8]]["cargo_capacity"] = 0
    var cache: Dictionary = {}
    var fittings: Dictionary = {}
    for qty in [1, 10, 20, 110, 200, 0]:
        for id in ids:
            assert(_cached(world, id, qty, cache) == _oracle(world, id, qty),
                "readiness mismatch " + id + " qty " + str(qty))
            var ship: Dictionary = world["ships"][id]
            var fitting: Dictionary = Dispatch._ship_flight_fitting(ship, id, fittings)
            var spec: Dictionary = Catalog.spec(str(ship.get("class", "")))
            assert(float(fitting["rate"]) == float(spec.get("fuel_consumption_base", 0.0)))
            assert(float(fitting["speed"]) == 1.25)
    # Mutations within one proposal are forbidden: test explicit invalidation
    # at the next propose boundary, including unchanged fleet size and IDs.
    world["ships"][ids[0]]["transit"] = {"to": "C"}
    world["ships"][ids[9]]["cargo"] = {"food": 2}
    world["ships"][ids[10]]["docked_at"] = "missing"
    world["ships"][ids[11]]["speed_modifier"] = 0.5
    cache = {}
    fittings = {}
    for id in ids:
        assert(_cached(world, id, 10, cache) == _oracle(world, id, 10))
    assert(float(Dispatch._ship_flight_fitting(world["ships"][ids[11]], ids[11], fittings)["speed"]) == 0.5)
    # Cache never owns a mutable ship or facility row.
    cache[ids[0]]["reason"] = "test_only"
    assert(not world["ships"][ids[0]].has("reason"))
    print("PASS p2_perf_c_n153_ship_static_readiness")
    quit(0)
