extends SceneTree
## Local regression for N14 physical last-leg fuel accounting.
## godot --headless --path godot --script res://tests/p2_ship_transit_fuel_check.gd
const ShipState = preload("res://scripts/sim/ship_state.gd")
const ShipTransit = preload("res://scripts/sim/ship_transit.gd")
const Catalog = preload("res://scripts/sim/ship_catalog.gd")

func _initialize() -> void:
    var state = ShipState.new()
    if not state.add_ship("test-miner", "miner", "terran-authority", "sol"):
        _fail("cannot initialize native miner")
        return
    var ship: Dictionary = state.ships["test-miner"]
    var speed: float = Catalog.effective_speed("miner", str(ship["size"]))
    var cost: float = float(Catalog.spec("miner")["fuel_consumption_base"])
    var distance: float = ShipTransit.BASE_VELOCITY * speed * 0.5
    if distance <= ShipTransit.ARRIVAL_THRESHOLD or cost <= 0.0:
        _fail("native ship velocity/fuel invalid for last-leg test")
        return
    var target := Vector2(distance, 0.0)
    ship["location"] = ""
    ship["fuel"] = cost * 0.5
    ship["transit"] = _flight(distance)
    var motion = ShipTransit.new()
    var blocked: String = motion.advance(state, "test-miner", {"station": target}, 1, 1.0)
    if blocked != "out_of_fuel" or not ship["location"].is_empty() or ship["transit"].is_empty():
        _fail("ship docked without fuel for final movement step")
        return
    if not is_equal_approx(float(ship["fuel"]), cost * 0.5):
        _fail("failed arrival consumed fuel")
        return
    ship["fuel"] = cost * 2.0
    var arrived: String = motion.advance(state, "test-miner", {"station": target}, 2, 1.0)
    if arrived != "arrived" or ship["location"] != "station" or not ship["transit"].is_empty():
        _fail("paid last-leg arrival rejected")
        return
    if not is_equal_approx(float(ship["fuel"]), cost):
        _fail("arrival didn't deduct exactly one native flight step")
        return
    print("P2_SHIP_LAST_LEG_FUEL_PASS")
    quit(0)

func _flight(distance: float) -> Dictionary:
    return {"from": "earth", "to": "station", "departure_tick": 0,
        "last_tick": 0, "arrival_tick": 1, "token": 1,
        "departure_position": [0.0, 0.0], "position": [0.0, 0.0],
        "distance_total": distance, "distance_travelled": 0.0}

func _fail(reason: String) -> void:
    push_error("P2_SHIP_LAST_LEG_FUEL_FAIL: " + reason)
    quit(1)
