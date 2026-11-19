extends RefCounted
## Physical N14 admission for source N80/N103 goal candidates only.
## Same fuel estimate already used by N153._ready_ship; actual N14
## always recalculates against moving orbital targets at departure/tick.
## No changes to fuel, cargo, time, ship state, balance or path graph.
const Catalog = preload("res://scripts/sim/ship_catalog.gd")
const Transit = preload("res://scripts/sim/ship_transit.gd")

## routes: [{"start": "real location", "nodes": [BT Travel action ...]}].
## A gate hop has NO N14 flight cost; the real N108/N9 fee is separate.
static func preflight(ship: Dictionary, positions: Dictionary,
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
    # The same directed leg may occur in several candidate BT routes.
    # Geometry belongs to this invocation only: moving orbital positions,
    # graph edits and N38 reloads cannot reuse a stale distance.
    # Cache ONLY validated geometry and integral edge ticks; fuel is accumulated per occurrence in
    # the original order so overflow, rounding and error priority are intact.
    var leg_ticks: Dictionary = {}
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
            var leg_key: Array = [current, to]
            var ticks: int
            if leg_ticks.has(leg_key):
                ticks = int(leg_ticks[leg_key])
            else:
                var a: Vector2 = positions[current]
                var target: Vector2 = positions[to]
                var distance: float = a.distance_to(target)
                if not is_finite(distance) or distance <= 0.0:
                    return {"ok": false, "reason": "n14_invalid_original_orbit_distance"}
                ticks = maxi(1, ceili(distance / velocity))
                leg_ticks[leg_key] = ticks
            # Same conservative N153 multi-leg estimate, no future
            # orbital prediction or optimistic early free arrival.
            # Keep multiplication and addition exactly as the uncached path.
            cost += float(ticks) * rate * tick_scale
            if not is_finite(cost):
                return {"ok": false, "reason": "n14_fuel_cost_overflow"}
            current = to
    if float(ship["fuel"]) + 0.0001 < cost:
        return {"ok": false, "reason": "n14_insufficient_real_multileg_fuel",
            "minimum": cost}
    return {"ok": true, "estimated_n14_fuel": cost}
