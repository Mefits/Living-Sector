extends SceneTree
## II-C N80 physical preflight: cached repeated directed legs vs original
## uncached loop. No fabricated flight, departure, cargo or N9 payment.
const Preflight = preload("res://scripts/sim/phase2/unified_n80_ship_route_fuel.gd")
const Catalog = preload("res://scripts/sim/ship_catalog.gd")
const Transit = preload("res://scripts/sim/ship_transit.gd")

func _oracle(ship: Dictionary, positions: Dictionary,
        tick_scale: float, routes: Array) -> Dictionary:
    if not is_finite(tick_scale) or tick_scale <= 0.0 or (
            not (ship.get("fuel") is int or ship.get("fuel") is float)):
        return {"ok": false, "reason": "n14_no_authoritative_fuel_clock"}
    var spec: Dictionary = Catalog.spec(str(ship.get("class", "")))
    var speed: float = float(ship.get("speed_modifier",
        Catalog.effective_speed(str(ship.get("class", "")),
            str(ship.get("size", "")))))
    var rate: float = float(spec.get("fuel_consumption_base", 0.0))
    if not is_finite(speed) or speed <= 0.0 or not is_finite(rate) or rate <= 0.0:
        return {"ok": false, "reason": "n14_invalid_original_ship_movement"}
    var velocity: float = Transit.BASE_VELOCITY * speed * tick_scale
    if not is_finite(velocity) or velocity <= 0.0:
        return {"ok": false, "reason": "n14_invalid_original_velocity"}
    var cost: float = 0.0
    for route in routes:
        if not (route is Dictionary) or not (route.get("nodes") is Array):
            return {"ok": false, "reason": "n14_invalid_route_segments"}
        var current: String = str(route.get("start", ""))
        for node in route["nodes"]:
            if not (node is Dictionary) or not (node.get("action") is Dictionary):
                return {"ok": false, "reason": "n14_nonphysical_route_leaf"}
            var action: Dictionary = node["action"]
            if str(action.get("kind", "")) != "Travel":
                return {"ok": false, "reason": "n14_nontravel_in_route"}
            var to: String = str(action.get("destination", ""))
            if current.is_empty() or to.is_empty() or current == to or (
                    not positions.has(current) or not positions.has(to) or
                    not (positions[current] is Vector2) or
                    not (positions[to] is Vector2)):
                return {"ok": false, "reason": "n14_missing_real_leg_geometry"}
            var a: Vector2 = positions[current]
            var target: Vector2 = positions[to]
            var distance: float = a.distance_to(target)
            if not is_finite(distance) or distance <= 0.0:
                return {"ok": false, "reason": "n14_invalid_original_orbit_distance"}
            cost += float(maxi(1, ceili(distance / velocity))) * rate * tick_scale
            if not is_finite(cost):
                return {"ok": false, "reason": "n14_fuel_cost_overflow"}
            current = to
    if float(ship["fuel"]) + 0.0001 < cost:
        return {"ok": false, "reason": "n14_insufficient_real_multileg_fuel",
            "minimum": cost}
    return {"ok": true, "estimated_n14_fuel": cost}

func _leg(to: String) -> Dictionary:
    return {"action": {"kind": "Travel", "destination": to}}

func _compare(ship: Dictionary, positions: Dictionary,
        scale: float, routes: Array) -> void:
    var expected: Dictionary = _oracle(ship, positions, scale, routes)
    var actual: Dictionary = Preflight.preflight(ship, positions, scale, routes)
    assert(actual == expected, "cached N80 diverged: " + str(actual) + " vs " + str(expected))

func _initialize() -> void:
    var ship: Dictionary = {"class": "small_transport", "size": "small",
        "speed_modifier": 1.0, "fuel": 1000000000.0}
    var positions: Dictionary = {"A": Vector2(0, 0), "B": Vector2(30, 40),
        "C": Vector2(80, 40), "D": Vector2(-40, 30)}
    var repeated: Array = [
        {"start": "A", "nodes": [_leg("B"), _leg("C"), _leg("A")]},
        {"start": "A", "nodes": [_leg("B"), _leg("C"), _leg("A")]},
        {"start": "B", "nodes": [_leg("A"), _leg("B"), _leg("D")]},
        {"start": "A", "nodes": [_leg("B"), _leg("C")]}]
    for scale in [0.125, 1.0, 16.0]:
        _compare(ship, positions, scale, repeated)
    # Opposite directed legs, repeated loops and changed orbital geometry.
    positions["B"] = Vector2(3000, 4000)
    _compare(ship, positions, 1.0, repeated)
    ship["fuel"] = 0.001
    _compare(ship, positions, 1.0, repeated)
    ship["fuel"] = 1000000000.0
    ship["speed_modifier"] = 0.25
    _compare(ship, positions, 1.0, repeated)
    ship["speed_modifier"] = 1.0
    _compare(ship, positions, 1.0, [{"start": "A", "nodes": [_leg("missing")]}])
    _compare(ship, positions, 1.0, [{"start": "A", "nodes": [_leg("A")]}])
    _compare(ship, positions, 1.0, [{"start": "A", "nodes": [{"action": {"kind": "Dock"}}]}])
    _compare(ship, positions, 1.0, [{"start": "A", "nodes": [false]}])
    _compare(ship, positions, 1.0, [{"start": "A", "nodes": "invalid"}])
    _compare(ship, positions, 0.0, repeated)
    _compare(ship, positions, NAN, repeated)
    ship["fuel"] = "invalid"
    _compare(ship, positions, 1.0, repeated)
    # Source dictionaries must remain untouched by cache construction.
    var before: Array = repeated.duplicate(true)
    ship["fuel"] = 1000000000.0
    _compare(ship, positions, 1.0, repeated)
    assert(repeated == before)
    print("P2_PERF_C_N80_ROUTE_LEG_CACHE_PASS")
    quit(0)
