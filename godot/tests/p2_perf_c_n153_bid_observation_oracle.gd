extends SceneTree
## N153 bid cache vs independent uncached source calculations.
const Dispatch = preload("res://scripts/sim/phase2/unified_n153_contract_dispatch.gd")

func _oracle_quote(qty: int, price: float, multiplier: float) -> Dictionary:
    var amount: float = ceil(float(qty) * price * multiplier)
    var valid: bool = is_finite(amount) and amount > 0.0 and amount <= 9007199254740991.0
    return {"valid": valid, "cost": int(amount) if valid else 0}

func _oracle_observation(ship: Dictionary) -> Dictionary:
    var sensor: Variant = ship.get("sensor_range_au", null)
    if not (sensor is int or sensor is float) or not is_finite(float(sensor)) or float(sensor) < 0.0:
        sensor = 2.0 if str(ship.get("size", "")) in ["huge", "massive"] else 1.0
    return {"sensor": float(sensor), "bonus": float(ship.get("comms_bonus", 0.0))}

func _initialize() -> void:
    var cache: Dictionary = {}
    for qty in [0, 1, 17, 100, 10000]:
        for price in [0.0, 0.001, 1.5, 99.99, 1.0e20]:
            cache.clear() # Each offer is a fresh quote scope.
            for multiplier in [0.5, 1.0, 1.25, 2.0, 1.25, 1.0]:
                assert(Dispatch._purchase_quote(cache, multiplier, qty, price) ==
                    _oracle_quote(qty, price, multiplier))
    # Negative: the same multiplier on another offer must not reuse old price.
    cache.clear()
    assert(Dispatch._purchase_quote(cache, 1.0, 2, 10.0)["cost"] == 20)
    cache.clear()
    assert(Dispatch._purchase_quote(cache, 1.0, 2, 30.0)["cost"] == 60)
    var ships: Dictionary = {}
    for i in range(120):
        var id: String = "ship_%03d" % i
        var ship: Dictionary = {"size": "huge" if i % 3 == 0 else "small",
            "comms_bonus": float(i % 11) / 100.0}
        if i % 4 == 0:
            ship["sensor_range_au"] = float(i) / 10.0
        elif i % 4 == 1:
            ship["sensor_range_au"] = -1.0
        elif i % 4 == 2:
            ship["sensor_range_au"] = "invalid"
        ships[id] = ship
    var observed: Dictionary = {}
    for repeat in range(12):
        for id in ships:
            assert(Dispatch._bid_observation(observed, id, ships[id]) ==
                _oracle_observation(ships[id]))
    # Negative: ownership of observations is detached from input ship rows.
    observed["ship_000"]["bonus"] = 0.77
    assert(float(ships["ship_000"]["comms_bonus"]) == 0.0)
    # Proposal boundary invalidates both price and ship observations.
    ships["ship_000"]["comms_bonus"] = 0.05
    ships["ship_001"]["sensor_range_au"] = 7.0
    observed.clear()
    assert(Dispatch._bid_observation(observed, "ship_000", ships["ship_000"]) ==
        _oracle_observation(ships["ship_000"]))
    assert(Dispatch._bid_observation(observed, "ship_001", ships["ship_001"]) ==
        _oracle_observation(ships["ship_001"]))
    print("PASS p2_perf_c_n153_bid_observation_oracle")
    quit(0)
