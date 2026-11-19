extends RefCounted
## Stable, camera-independent SOL MAP-SPACE flight route for both small ships.
##
## Same geometric principle as SystemBalance/native_avoidance.gd:
## direct path unless an exclusion circle intersects it, otherwise tangent
## approach -> bounded circular arc -> tangent departure. This ONLY decides
## where a visual marker is rendered. The simulation owns arrival and cargo.
##
## Points use the SAME compressed orbital world coordinates as Sol Lab bodies,
## BEFORE viewport center, pan, zoom and UI scaling. Reproject during draw.
const MAX_ARC_ANGLE: float = PI / 12.0
const MAX_POINTS_PER_ARC: int = 24
const DETOUR_RADIUS_MULTIPLIER: float = 1.25
const MAX_DETOURS: int = 4
const INTERSECTION_EPSILON: float = 0.000001

static func fraction(departure: float, arrival: float, visual_time: float) -> float:
    if arrival <= departure:
        return 1.0
    return clampf((visual_time - departure) / (arrival - departure), 0.0, 1.0)


static func segment_crosses(start: Vector2, target: Vector2,
        center: Vector2, radius: float) -> bool:
    if radius <= 0.0 or not is_finite(radius):
        return false
    if start.distance_squared_to(center) <= radius * radius or (
            target.distance_squared_to(center) <= radius * radius):
        return true
    var step: Vector2 = target - start
    var length_sq: float = step.length_squared()
    if length_sq <= 0.0:
        return false
    var projected: float = clampf(
        (center - start).dot(step) / length_sq, 0.0, 1.0)
    var nearest: Vector2 = start + step * projected
    return nearest.distance_squared_to(center) < (
        radius * radius * (1.0 - INTERSECTION_EPSILON))


## Ported geometry from SystemBalance's native_avoidance.gd, with Vector2
## instead of native N14 waypoint receipts. NEVER charge fuel or move ships.
static func _tangent_arc(start: Vector2, target: Vector2,
        center: Vector2, radius: float) -> Dictionary:
    var origin: Vector2 = start - center
    var goal: Vector2 = target - center
    var origin_distance: float = origin.length()
    var goal_distance: float = goal.length()
    if origin_distance <= radius or goal_distance <= radius:
        return {}
    var outer: float = minf(radius * DETOUR_RADIUS_MULTIPLIER,
        minf(origin_distance, goal_distance) * 0.995)
    if outer <= radius:
        return {}
    var start_angle: float = origin.angle()
    var finish_angle: float = goal.angle()
    var tangent_start: float = acos(clampf(outer / origin_distance, 0.0, 1.0))
    var tangent_finish: float = acos(clampf(outer / goal_distance, 0.0, 1.0))
    var ccw: float = fposmod(finish_angle - tangent_finish - (
        start_angle + tangent_start), TAU)
    var cw: float = fposmod(start_angle - tangent_start - (
        finish_angle + tangent_finish), TAU)
    var windings: Array = [1.0, -1.0] if ccw <= cw else [-1.0, 1.0]
    for winding_value in windings:
        var winding: float = float(winding_value)
        var start_tangent: float = start_angle + winding * tangent_start
        var finish_tangent: float = finish_angle - winding * tangent_finish
        var sweep: float = (
            fposmod(finish_tangent - start_tangent, TAU)
            if winding > 0.0 else
            -fposmod(start_tangent - finish_tangent, TAU))
        var steps: int = maxi(1, ceili(absf(sweep) / MAX_ARC_ANGLE))
        if steps + 1 > MAX_POINTS_PER_ARC:
            continue
        var curve := PackedVector2Array()
        var prior: Vector2 = start
        var safe: bool = true
        for index in range(steps + 1):
            var angle: float = start_tangent + (
                sweep * float(index) / float(steps))
            var point: Vector2 = center + Vector2(
                cos(angle), sin(angle)) * outer
            if segment_crosses(prior, point, center, radius):
                safe = false
                break
            curve.append(point)
            prior = point
        if safe and not segment_crosses(prior, target, center, radius):
            return {"points": curve}
    return {}


## A direct line remains EXACTLY straight. Detour only for an obstructed
## segment, with at most four bounded SystemBalance-style tangent arcs.
## All obstacles must already be in camera-independent Sol map units.
static func plan(start: Vector2, destination: Vector2,
        obstacles: Array = []) -> Dictionary:
    var points := PackedVector2Array([start, destination])
    var bypassed: Array[String] = []
    for obstacle in obstacles:
        if bypassed.size() >= MAX_DETOURS:
            break
        if not (obstacle is Dictionary):
            continue
        var center: Vector2 = obstacle.get("center", Vector2.ZERO)
        var radius: float = float(obstacle.get("radius", 0.0))
        if radius <= 0.0:
            continue
        var updated := PackedVector2Array([points[0]])
        var routed: bool = false
        for i in range(1, points.size()):
            var prior: Vector2 = points[i - 1]
            var following: Vector2 = points[i]
            if not routed and segment_crosses(
                    prior, following, center, radius):
                var arc: Dictionary = _tangent_arc(
                    prior, following, center, radius)
                if not arc.is_empty():
                    updated.append_array(arc["points"])
                    routed = true
            updated.append(following)
        if routed:
            points = updated
            bypassed.append(str(obstacle.get("id", "obstacle")))
    var lengths := PackedFloat64Array([0.0])
    var total: float = 0.0
    for index in range(1, points.size()):
        total += points[index].distance_to(points[index - 1])
        lengths.append(total)
    return {"points": points, "lengths": lengths, "total": total,
        "detours": bypassed}


## Constant visual distance per unit of GAME time. Segment lengths, not
## equal waypoint counts, drive the position and ship tangent direction.
static func sample(route: Dictionary, progress: float) -> Dictionary:
    var points: PackedVector2Array = route.get("points", PackedVector2Array())
    var lengths: PackedFloat64Array = route.get(
        "lengths", PackedFloat64Array())
    if points.size() < 2 or lengths.size() != points.size():
        return {"position": Vector2.ZERO, "direction": Vector2.RIGHT}
    var total: float = float(route.get("total", 0.0))
    if total <= 0.000001:
        return {"position": points[points.size() - 1],
            "direction": Vector2.RIGHT}
    var distance: float = clampf(progress, 0.0, 1.0) * total
    for index in range(1, points.size()):
        if distance > lengths[index] and index < points.size() - 1:
            continue
        var length: float = lengths[index] - lengths[index - 1]
        var alpha: float = (
            (distance - lengths[index - 1]) / length if length > 0.0 else 1.0)
        var from: Vector2 = points[index - 1]
        var to: Vector2 = points[index]
        var forward: Vector2 = (to - from).normalized()
        return {"position": from.lerp(to, clampf(alpha, 0.0, 1.0)),
            "direction": forward if forward.length_squared() > 0.0 else Vector2.RIGHT}
    return {"position": points[points.size() - 1],
        "direction": (points[points.size() - 1] -
            points[points.size() - 2]).normalized()}
