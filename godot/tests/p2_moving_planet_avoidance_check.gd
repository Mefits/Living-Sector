extends SceneTree
## Verified moving-planet obstacles are a native N43/N14 route input.
## This test uses authentic frozen Sol Earth coordinates and a synthetic
## directed fixture route to force a crossing without inventing a World site.
const NativeData = preload("res://scripts/native_data.gd")
const Model = preload("res://scripts/sim/world_model.gd")
const Resolver = preload("res://scripts/sim/ships/native_location_resolver.gd")
const Avoidance = preload("res://scripts/sim/ships/native_avoidance.gd")
const State = preload("res://scripts/sim/ship_state.gd")
const Transit = preload("res://scripts/sim/ship_transit.gd")

class Graph:
    extends RefCounted
    func outgoing(origin: String) -> Array:
        if origin == "start":
            return [{"from": "start", "to": "target"}]
        return []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    var model: RefCounted = Model.new()
    var resolver: RefCounted = Resolver.new()
    if seed.has("error") or not model.load_seed(seed) or (
            not resolver.load_seed(seed)):
        _fail("real frozen Sol source unavailable")
        return
    var obstacles: Array = resolver.verified_planet_obstacles(
        "system-sol", model)
    if obstacles.size() < 7 or obstacles.size() > 16:
        _fail("bounded Sol physical planet obstacle registry missing")
        return
    if not resolver.verified_planet_obstacles(
            "system-alpha-centauri", model).is_empty():
        _fail("unverified foreign system was assigned fictitious radii")
        return
    var earth: Dictionary = {}
    for obstacle in obstacles:
        if str(obstacle.get("id", "")) == "earth":
            earth = obstacle
    if earth.is_empty() or earth["center"].distance_to(
            Vector2(2.0, 0.0)) > 0.00001:
        _fail("Earth obstacle not at real N43 orbit")
        return
    var body: Dictionary = resolver.body_universe_position("earth", model)
    if not body.get("ok", false) or (
            body["position"].distance_to(earth["center"]) > 0.000001):
        _fail("N43 obstacle differs from actual body position")
        return
    var radius: float = float(earth["radius"])
    if radius < 0.00008 or radius > 0.00010:
        _fail("Earth obstruction uses fake UI icon radius")
        return
    if not Avoidance.segment_crosses(
            Vector2(3.0, 0.0), Vector2(1.0, 0.0),
            earth["center"], radius):
        _fail("physical planet collision was ignored")
        return
    var state: RefCounted = State.new()
    if not state.add_ship("ship", "courier", "test-faction",
            "system-sol", "small"):
        _fail("cannot create N14 test vessel")
        return
    state.ships["ship"]["location"] = "start"
    var transit: RefCounted = Transit.new()
    var positions: Dictionary = {
        "start": Vector2(3.0, 0.0),
        "target": Vector2(1.0, 0.0)
    }
    if not transit.depart(state, Graph.new(), "ship",
            "target", positions, 0, 1.0):
        _fail("directed source-to-target leg rejected")
        return
    var fuel_before: float = float(state.ships["ship"]["fuel"])
    var first: String = transit.advance(state, "ship", positions,
        1, 1.0, 1, false, {}, 0.000005, {}, [earth])
    if first != "moving" or state.ships["ship"]["transit"].get(
            "navigation_obstacle_id", "") != "earth":
        _fail("moving planet did not generate persistent real arc")
        return
    var prior: Dictionary = state.ships["ship"]["transit"]
    var p: Vector2 = Vector2(float(prior["position"][0]),
        float(prior["position"][1]))
    var to_waypoint: Array = prior["navigation_waypoints"][0]
    var next: Vector2 = Vector2(float(to_waypoint[0]),
        float(to_waypoint[1]))
    var artificial_moving_obstacle: Dictionary = {
        "id": "moving-planet-fixture",
        "center": p.lerp(next, 0.04),
        "radius": 0.02
    }
    # A new moving planet can intrude on a previously clear path.
    # The ship must hold without teleport or fuel charge.
    var fuel_on_hold: float = float(state.ships["ship"]["fuel"])
    var holding: String = transit.advance(state, "ship", positions,
        2, 1.0, 1, false, {}, 0.000005, {},
        [earth, artificial_moving_obstacle])
    if holding != "holding" or (
            absf(float(state.ships["ship"]["fuel"]) -
            fuel_on_hold) > 0.000001) or (
            state.ships["ship"]["transit"]["position"] != [p.x, p.y]):
        _fail("moving obstacle failed closed without free motion/fuel")
        return

    var end_tick: int = -1
    var old: Vector2 = p
    for tick in range(3, 110):
        var outcome: String = transit.advance(state, "ship", positions,
            tick, 1.0, 1, false, {}, 0.000005, {}, [earth])
        if outcome == "arrived":
            if old.distance_to(positions["target"]) > 0.08:
                _fail("arrival after physical detour teleported")
                return
            end_tick = tick
            break
        if outcome != "moving":
            _fail("planet avoidance could not resume after obstruction: " +
                outcome)
            return
        var current: Dictionary = state.ships["ship"]["transit"]
        var moved: Vector2 = Vector2(float(current["position"][0]),
            float(current["position"][1]))
        if Avoidance.segment_crosses(
                old, moved, earth["center"], radius):
            _fail("ship physically crossed the planet while turning")
            return
        old = moved
    if end_tick < 0 or not state.ships["ship"]["transit"].is_empty():
        _fail("detour never reached valid native destination")
        return
    if float(state.ships["ship"]["fuel"]) >= fuel_before:
        _fail("planet avoidance consumed no physical flight fuel")
        return
    model.advance_orbits(2.0)
    var moved_obstacles: Array = resolver.verified_planet_obstacles(
        "system-sol", model)
    var moved_earth: Vector2 = Vector2.ZERO
    for obstruction in moved_obstacles:
        if obstruction["id"] == "earth":
            moved_earth = obstruction["center"]
    if moved_earth.distance_to(earth["center"]) <= 0.001:
        _fail("obstacle registry did not track moving native planet")
        return
    print("P2 MOVING PLANET AVOIDANCE PASS: ", end_tick,
        " physically paid N14 ticks; obstruction hold and resume;",
        " canonical Earth native radius and N43 positions")
    quit(0)


func _fail(reason: String) -> void:
    push_error("P2 MOVING PLANET AVOIDANCE FAIL: " + reason)
    quit(1)
