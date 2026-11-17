extends SceneTree
## SystemBalance: actual tangent-course geometry and multi-chord movement.
## These are real N14 ship positions, not render-time curve points.
const Avoidance = preload("res://scripts/sim/ships/native_avoidance.gd")
const Transit = preload("res://scripts/sim/ship_transit.gd")
const State = preload("res://scripts/sim/ship_state.gd")
const Catalog = preload("res://scripts/sim/ship_catalog.gd")

class Graph:
    extends RefCounted
    func outgoing(origin: String) -> Array:
        if origin == "start":
            return [{"from": "start", "to": "target"}]
        return []


func _initialize() -> void:
    call_deferred("_check")


func _check() -> void:
    var origin: Vector2 = Vector2(-2.0, 0.0)
    var goal: Vector2 = Vector2(2.0, 0.0)
    var center: Vector2 = Vector2.ZERO
    var radius: float = 0.8
    var p: Dictionary = Avoidance.plan(origin, goal, center, radius)
    if not p.get("ok", false) or not Avoidance.valid_stored_points(
            p.get("points", null)):
        _fail("tangent path not produced")
        return
    var points: Array = p["points"]
    if points.size() < 4 or points.size() > Avoidance.MAX_POINTS:
        _fail("physical arc was not sampled within fixed point budget")
        return
    if Avoidance.plan(origin, goal, center, radius)["points"] != points:
        _fail("native tangent course is not deterministic")
        return
    var all: Array[Vector2] = [origin]
    for raw in points:
        all.append(Vector2(float(raw[0]), float(raw[1])))
    all.append(goal)
    var length: float = 0.0
    for i in range(all.size() - 1):
        if Avoidance.segment_crosses(all[i], all[i + 1],
                center, radius):
            _fail("actual native arc chord crossed exclusion zone")
            return
        length += all[i].distance_to(all[i + 1])
    if length <= origin.distance_to(goal):
        _fail("detour length does not include the physical arc")
        return
    # At the tangent-to-arc junction the heading must not snap by
    # 90 degrees. Small polyline chord angles approximate a C1 path.
    for i in range(1, all.size() - 1):
        var inbound: Vector2 = (all[i] - all[i - 1]).normalized()
        var outbound: Vector2 = (all[i + 1] - all[i]).normalized()
        if inbound.dot(outbound) < 0.95:
            _fail("course has a sharp turn instead of tangent smoothing")
            return

    # Real radius ~9e-5: the old 1e-6 squared cutoff silently failed
    # on individual short segments around an Earth-sized body.
    var small: Vector2 = Vector2(2.0, 0.0)
    if not Avoidance.segment_crosses(
            small + Vector2(-0.000095, 0.0),
            small + Vector2(0.000095, 0.0),
            small, 0.00009):
        _fail("tiny physical planet collision was incorrectly ignored")
        return

    var state: RefCounted = State.new()
    if not state.add_ship("probe", "courier",
            "fixture-faction", "system-sol", "small"):
        _fail("real N14 vessel unavailable")
        return
    var start_point: Vector2 = all[1]
    var locations: Dictionary = {"start": start_point, "target": goal}
    state.ships["probe"]["location"] = "start"
    var flight: RefCounted = Transit.new()
    if not flight.depart(state, Graph.new(),
            "probe", "target", locations, 0, 8.0):
        _fail("authentic N14 receipt could not be started")
        return
    var receipt: Dictionary = state.ships["probe"]["transit"]
    receipt["navigation_waypoints"] = points.duplicate(true)
    receipt["navigation_obstacle_id"] = "sol-star"
    var fuel_before: float = float(state.ships["probe"]["fuel"])
    var first: String = flight.advance(state, "probe", locations,
        1, 8.0, 1, false, {}, 0.00001,
        {"id": "sol-star", "center": center, "radius": radius})
    if first != "moving":
        _fail("authentic N14 course did not advance: " + first)
        return
    var remaining: Array = state.ships["probe"]["transit"].get(
        "navigation_waypoints", [])
    if remaining.size() > points.size() - 2:
        _fail("tiny arc chords consumed separate whole native ticks")
        return
    var moved: float = float(state.ships["probe"]["transit"].get(
        "physical_distance_travelled", 0.0))
    var maximum: float = Transit.BASE_VELOCITY * (
        Catalog.effective_speed("courier", "small")) * 8.0
    if moved <= 0.01 or moved > maximum + 0.00001:
        _fail("multi-chord advance violated real N14 speed budget")
        return
    var paid: float = float(Catalog.spec("courier")[
        "fuel_consumption_base"]) * 8.0
    if absf(float(state.ships["probe"]["fuel"]) -
            (fuel_before - paid)) > 0.000001:
        _fail("one real native movement charged multiple fuel ticks")
        return
    var saved: Array = state.snapshot()
    var loaded: RefCounted = State.new()
    if not loaded.restore(saved) or loaded.ships[
            "probe"]["transit"] != state.ships["probe"]["transit"]:
        _fail("smoothed course failed N39-style save/restore")
        return

    # Continue physically. No teleports to the destination regardless
    # of how many circular-arc chords were consumed in earlier ticks.
    var arrival: int = -1
    var previous: Vector2 = Vector2(
        float(receipt["position"][0]), float(receipt["position"][1]))
    for tick in range(2, 30):
        var result: String = flight.advance(state, "probe", locations,
            tick, 8.0, 1, false, {}, 0.00001,
            {"id": "sol-star", "center": center, "radius": radius})
        if result == "arrived":
            if previous.distance_to(goal) > maximum + 0.00001:
                _fail("final docking skipped real physical flight")
                return
            arrival = tick
            break
        if result != "moving":
            _fail("smoothed native route stopped: " + result)
            return
        var live: Dictionary = state.ships["probe"]["transit"]
        var next_position: Vector2 = Vector2(
            float(live["position"][0]), float(live["position"][1]))
        if previous.distance_to(next_position) > maximum + 0.00001:
            _fail("course exceeded native velocity in one tick")
            return
        if Avoidance.segment_crosses(
                previous, next_position, center, radius):
            _fail("finished course crossed physical Sun")
            return
        previous = next_position
    if arrival < 0:
        _fail("smoothed N14 ship never completed its physical course")
        return
    # Even if a destination is within ONE tick of native velocity,
    # the direct arrival must NOT jump through the real star zone.
    var near_state: RefCounted = State.new()
    if not near_state.add_ship("near", "courier",
            "fixture-faction", "system-sol", "small"):
        _fail("near-final-approach fixture missing")
        return
    near_state.ships["near"]["location"] = "start"
    var near_transit: RefCounted = Transit.new()
    var near_positions: Dictionary = {
        "start": Vector2(-0.03, 0.0),
        "target": Vector2(0.03, 0.0)}
    if not near_transit.depart(near_state, Graph.new(),
            "near", "target", near_positions, 0, 1.0):
        _fail("real near-star final approach cannot depart")
        return
    var near_result: String = near_transit.advance(
        near_state, "near", near_positions, 1, 1.0, 1, false,
        {}, 0.00001, {
            "id": "sol-star", "center": Vector2.ZERO, "radius": 0.02})
    if near_result != "moving" or not str(
            near_state.ships["near"]["location"]).is_empty():
        _fail("one-tick final docking was allowed through Sun: " +
            near_result)
        return
    # The WHOLE true curved physical path may be completed inside one
    # tick and the waypoint receipt cleared; comparing only the two
    # frame endpoints would incorrectly claim a straight collision.
    var near_old: Vector2 = near_positions["start"]
    var near_pos: Array = near_state.ships["near"]["transit"]["position"]
    var near_actual: Vector2 = Vector2(
        float(near_pos[0]), float(near_pos[1]))
    var near_distance: float = float(near_state.ships["near"]["transit"].get(
        "physical_distance_travelled", 0.0))
    if near_actual.length() <= 0.02 or near_distance <= (
            near_old.distance_to(near_actual) + 0.001):
        _fail("final approach did not physically traverse the Sun detour")
        return

    print("P2 SMOOTH N14 PASS: tangent arc points=", points.size(),
        ", moved=", snappedf(moved, 0.001), " native on first tick, ",
        "waypoints traversed=", points.size() - remaining.size(),
        ", arrival_tick=", arrival, "; safe 500-ship-compatible bound")
    quit(0)


func _fail(reason: String) -> void:
    push_error("P2 SMOOTH N14 FAIL: " + reason)
    quit(1)
