extends RefCounted
## Deterministic native N14 navigation: tangent approach + shallow
## circular arc + tangent departure. Ship traverses the actual stored
## points and burns real fuel. This is NOT rendered-only Bezier art.
## Max ~15 degrees per physical chord; bounded once-per-detour work.
const MAX_POINTS: int = 24
const MAX_ARC_ANGLE: float = PI / 12.0
const DETOUR_RADIUS_MULTIPLIER: float = 1.25
const INTERSECTION_RELATIVE_EPS: float = 0.000001


static func segment_crosses(start: Vector2, target: Vector2,
        center: Vector2, radius: float) -> bool:
    if radius <= 0.0 or not is_finite(radius):
        return false
    if start.distance_squared_to(center) < radius * radius or (
            target.distance_squared_to(center) < radius * radius):
        return true
    var delta: Vector2 = target - start
    var length_sq: float = delta.length_squared()
    if length_sq <= 0.000000000001:
        return false
    var projection: float = clampf(
        (center - start).dot(delta) / length_sq, 0.0, 1.0)
    var closest: Vector2 = start + delta * projection
    return closest.distance_squared_to(center) < (
        radius * radius * (1.0 - INTERSECTION_RELATIVE_EPS))


## At each endpoint choose one of the two mathematically tangent
## connections to an outer safety circle; retain the shorter safe arc.
## The tangent-to-arc join is C1 in continuous geometry, with short
## straight chords approximating curvature in the native movement.
## Only MAX_POINTS stored in one N39 receipt. Never add a fake UI path.
static func plan(start: Vector2, target: Vector2,
        center: Vector2, radius: float) -> Dictionary:
    if not (is_finite(start.x) and is_finite(start.y) and
            is_finite(target.x) and is_finite(target.y) and
            is_finite(center.x) and is_finite(center.y) and
            is_finite(radius)) or radius <= 0.0:
        return {"ok": false, "reason": "invalid_navigation_geometry"}
    if not segment_crosses(start, target, center, radius):
        return {"ok": true, "points": []}
    var origin: Vector2 = start - center
    var goal: Vector2 = target - center
    var origin_distance: float = origin.length()
    var goal_distance: float = goal.length()
    if origin_distance <= radius or goal_distance <= radius:
        return {"ok": false, "reason": "endpoint_inside_solar_exclusion"}
    var outer_radius: float = minf(radius * DETOUR_RADIUS_MULTIPLIER,
        minf(origin_distance, goal_distance) * 0.995)
    if outer_radius <= radius:
        return {"ok": false, "reason": "insufficient_tangent_clearance"}
    var angle_origin: float = origin.angle()
    var angle_goal: float = goal.angle()
    var tangent_origin: float = acos(clampf(
        outer_radius / origin_distance, 0.0, 1.0))
    var tangent_goal: float = acos(clampf(
        outer_radius / goal_distance, 0.0, 1.0))
    var best_length: float = INF
    var best_points: Array = []
    # Evaluate both winding directions, deterministic tie preference.
    for winding in [1.0, -1.0]:
        var from_angle: float = angle_origin + winding * tangent_origin
        var to_angle: float = angle_goal - winding * tangent_goal
        var sweep: float = (
            fposmod(to_angle - from_angle, TAU)
            if winding > 0.0 else -fposmod(from_angle - to_angle, TAU))
        var steps: int = maxi(1, ceili(
            absf(sweep) / MAX_ARC_ANGLE))
        if steps + 1 > MAX_POINTS:
            continue
        var candidates: Array = []
        for index in range(steps + 1):
            var angle: float = from_angle + (
                sweep * float(index) / float(steps))
            var point: Vector2 = center + Vector2(
                cos(angle), sin(angle)) * outer_radius
            candidates.append([point.x, point.y])
        var current: Vector2 = start
        var valid: bool = true
        var travel: float = 0.0
        for pair in candidates:
            var next_point: Vector2 = Vector2(float(pair[0]),
                float(pair[1]))
            if segment_crosses(current, next_point, center, radius):
                valid = false
                break
            travel += current.distance_to(next_point)
            current = next_point
        if not valid or segment_crosses(current, target, center, radius):
            continue
        travel += current.distance_to(target)
        if travel < best_length:
            best_length = travel
            best_points = candidates
    if best_points.is_empty():
        return {"ok": false, "reason": "no_safe_tangent_arc"}
    return {"ok": true, "points": best_points}


static func valid_stored_points(points: Variant) -> bool:
    if not (points is Array) or points.size() > MAX_POINTS:
        return false
    for point in points:
        if not (point is Array) or point.size() != 2:
            return false
        if not ((point[0] is float or point[0] is int) and
                (point[1] is float or point[1] is int)):
            return false
        if not (is_finite(float(point[0])) and
                is_finite(float(point[1]))):
            return false
    return true
