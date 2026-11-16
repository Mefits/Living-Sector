extends RefCounted
## P2: deterministic native-coordinate moving-target intercept.
## This is NOT rendered space, does not move the destination and does not
## change fuel, docking, routes, money, or native tick duration.
## A trajectory is {center: Vector2, components: [{radius, angle, period},...]}.
## Components represent nested circular orbits (planet, moon, station).
const MAX_COMPONENTS: int = 4
const BRACKET_SAMPLES: int = 64
const BISECTION_STEPS: int = 24

static func valid_trajectory(trajectory: Dictionary) -> bool:
    var center: Variant = trajectory.get("center", null)
    var components: Variant = trajectory.get("components", null)
    if not (center is Vector2) or not is_finite(center.x) or (
            not is_finite(center.y)):
        return false
    if not (components is Array) or components.is_empty() or (
            components.size() > MAX_COMPONENTS):
        return false
    for component in components:
        if not (component is Dictionary):
            return false
        var orbit: Dictionary = component
        for key in ["radius", "angle", "period"]:
            var value: Variant = orbit.get(key, null)
            if not (value is float or value is int) or (
                    not is_finite(float(value))):
                return false
        if float(orbit["radius"]) < 0.0 or float(orbit["period"]) <= 0.0:
            return false
    return true


## Native world position after a specified number of native time units.
static func position_after(trajectory: Dictionary, native_dt: float) -> Vector2:
    var result: Vector2 = trajectory.get("center", Vector2.ZERO)
    for component in trajectory.get("components", []):
        var angle: float = deg_to_rad(float(component["angle"]) +
            360.0 * native_dt / float(component["period"]))
        result += Vector2(cos(angle), sin(angle)) * float(component["radius"])
    return result


## Conservative upper bound for the velocity of a nested circular
## target (triangle inequality for all orbital components).
static func maximum_orbital_speed(trajectory: Dictionary) -> float:
    var upper: float = 0.0
    for component in trajectory.get("components", []):
        upper += TAU * float(component["radius"]) / float(component["period"])
    return upper


## Earliest catch at constant ship speed: solve
##   distance(ship, destination(t)) = speed * t .
## Check the earliest root, not a single extrapolated waypoint. Return
## no_solution if this flight cannot reach its target in the horizon.
static func intercept(ship_position: Vector2, speed: float,
        trajectory: Dictionary, horizon: float) -> Dictionary:
    if not is_finite(ship_position.x) or not is_finite(ship_position.y) or (
            not is_finite(speed)) or speed <= 0.0 or (
            not is_finite(horizon)) or horizon <= 0.0 or (
            not valid_trajectory(trajectory)):
        return {"ok": false, "reason": "invalid_intercept_input"}
    var current: Vector2 = position_after(trajectory, 0.0)
    if ship_position.distance_to(current) <= 0.000001:
        return {"ok": true, "time": 0.0, "point": current}
    var low: float = 0.0
    var high: float = horizon
    var bound: float = maximum_orbital_speed(trajectory)
    if speed > bound:
        # f(t) = distance(ship, target(t)) - speed * t decreases
        # strictly because |target_velocity| <= bound < ship_speed.
        # Thus the first root is unique: skip the expensive 64-point
        # orbital scan entirely and bisect its proven bracket.
        var high_value: float = ship_position.distance_to(
            position_after(trajectory, high)) - speed * high
        if high_value > 0.0:
            return {"ok": false, "reason": "no_solution_in_horizon"}
    else:
        # A slower ship can have several intercept windows. Scan to
        # bracket the FIRST root; never pick an arbitrary late crossing.
        var low_value: float = ship_position.distance_to(current)
        var found: bool = false
        for sample in range(1, BRACKET_SAMPLES + 1):
            high = horizon * float(sample) / float(BRACKET_SAMPLES)
            var destination: Vector2 = position_after(trajectory, high)
            var high_value: float = (
                ship_position.distance_to(destination) - speed * high)
            if high_value <= 0.0 and low_value > 0.0:
                found = true
                break
            low = high
            low_value = high_value
        if not found:
            return {"ok": false, "reason": "no_solution_in_horizon"}
    for _i in range(BISECTION_STEPS):
        var mid: float = (low + high) * 0.5
        var test: float = ship_position.distance_to(
            position_after(trajectory, mid)) - speed * mid
        if test > 0.0:
            low = mid
        else:
            high = mid
    var when: float = (low + high) * 0.5
    return {"ok": true, "time": when,
        "point": position_after(trajectory, when)}


## When we cannot predict the target safely, keep the original Rust
## pursuit trajectory. Never substitute a fake position or teleport.
static func aim_point(ship_position: Vector2, speed: float,
        trajectory: Dictionary, actual_target: Vector2) -> Dictionary:
    if not valid_trajectory(trajectory):
        return {"point": actual_target, "prediction_used": false}
    # Limit the scan to a bounded useful horizon in native time.
    var distance_now: float = ship_position.distance_to(actual_target)
    var estimate: float = distance_now / maxf(speed, 0.000001)
    var horizon: float = estimate * 3.0 + 10.0
    var bound: float = maximum_orbital_speed(trajectory)
    if bound < speed:
        # Enough time for a guaranteed catch, as long as it fits the
        # intentionally bounded native forecast horizon.
        horizon = maxf(horizon, distance_now / (speed - bound) + 1.0)
    horizon = clampf(horizon, 10.0, 2048.0)
    var result: Dictionary = intercept(ship_position, speed,
        trajectory, horizon)
    if not result.get("ok", false):
        return {"point": actual_target, "prediction_used": false}
    return {"point": result["point"], "prediction_used": true,
        "eta_native": result["time"]}
