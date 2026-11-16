extends RefCounted
## N14 bounded, deterministic native-coordinate star avoidance.
## A few waypoints are stored in the canonical transit receipt, never
## recomputed by _draw or every native tick during a detour.
## This is a deliberately limited first-stage solar exclusion-zone route,
## not general N-body physics, satellite or star gravity, or fake UI curves.
const MAX_POINTS: int = 8
const ANGULAR_SEGMENT: float = PI / 6.0
const DETOUR_RADIUS_MULTIPLIER: float = 1.5
## Relative comparison is essential: physical Earth radius is ~0.000085
## native, so an absolute 1e-6 squared tolerance would erase the planet.
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


## If both endpoints are outside the exclusion zone, choose a shallow
## outer arc around it. Actual ship movement follows these segments,
## does not teleport between nodes or cut the physical corner.
## A physically impossible route fails closed rather than inserting
## unsafe, arbitrary render-only vertices.
static func plan(start: Vector2, target: Vector2,
        center: Vector2, radius: float) -> Dictionary:
    if not (is_finite(start.x) and is_finite(start.y) and
            is_finite(target.x) and is_finite(target.y) and
            is_finite(center.x) and is_finite(center.y) and
            is_finite(radius)) or radius <= 0.0:
        return {"ok": false, "reason": "invalid_navigation_geometry"}
    if not segment_crosses(start, target, center, radius):
        return {"ok": true, "points": []}
    var a: Vector2 = start - center
    var b: Vector2 = target - center
    if a.length() <= radius or b.length() <= radius:
        return {"ok": false, "reason": "endpoint_inside_solar_exclusion"}
    var angle_a: float = a.angle()
    var angle_b: float = b.angle()
    var sweep: float = wrapf(angle_b - angle_a, -PI, PI)
    var steps: int = clampi(ceili(absf(sweep) / ANGULAR_SEGMENT), 2, 6)
    var arc_radius: float = radius * DETOUR_RADIUS_MULTIPLIER
    var vertices: Array[Vector2] = []
    if a.length() < arc_radius:
        vertices.append(center + a.normalized() * arc_radius)
    for i in range(1, steps):
        var angle: float = angle_a + sweep * float(i) / float(steps)
        vertices.append(center + Vector2(cos(angle), sin(angle)) * arc_radius)
    if b.length() < arc_radius:
        vertices.append(center + b.normalized() * arc_radius)
    if vertices.is_empty() or vertices.size() > MAX_POINTS:
        return {"ok": false, "reason": "navigation_waypoints_exceeded"}
    var last: Vector2 = start
    for point in vertices:
        if segment_crosses(last, point, center, radius):
            return {"ok": false, "reason": "navigation_arc_not_clear"}
        last = point
    if segment_crosses(last, target, center, radius):
        return {"ok": false, "reason": "navigation_final_leg_not_clear"}
    var stored: Array = []
    for point in vertices:
        stored.append([point.x, point.y])
    return {"ok": true, "points": stored}


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
