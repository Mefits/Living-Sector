extends SceneTree
## Real Godot headless acceptance for opt-in N14 orbit prediction:
## godot --headless --path godot --script res://tests/p2_native_orbital_intercept_check.gd
const NativeData = preload("res://scripts/native_data.gd")
const WorldModel = preload("res://scripts/sim/world_model.gd")
const Resolver = preload("res://scripts/sim/ships/native_location_resolver.gd")
const Intercept = preload("res://scripts/sim/ships/native_orbital_intercept.gd")
const Transit = preload("res://scripts/sim/ship_transit.gd")
const State = preload("res://scripts/sim/ship_state.gd")
const Catalog = preload("res://scripts/sim/ship_catalog.gd")

class StubGraph:
    extends RefCounted
    func outgoing(origin: String) -> Array:
        if origin == "start":
            return [{"from": "start", "to": "target"}]
        return []


func _initialize() -> void:
    call_deferred("_check")


func _check() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("frozen seed missing: " + str(seed["error"]))
        return
    var original: String = JSON.stringify(seed)
    var model: RefCounted = WorldModel.new()
    var resolver: RefCounted = Resolver.new()
    if not model.load_seed(seed) or not resolver.load_seed(seed):
        _fail("N43 frozen seed cannot be loaded")
        return
    var native_zero: Dictionary = resolver.positions_from_world(model, 0.0)
    var predicted: Dictionary = resolver.ephemeris_for_location(
        "earth-station", model, 0.0)
    if not native_zero.get("ok", false) or not predicted.get("ok", false):
        _fail("Earth station native ephemeris not available")
        return
    var path: Dictionary = predicted["trajectory"]
    if not Intercept.valid_trajectory(path):
        _fail("real Earth station ephemeris invalid")
        return
    var actual_zero: Vector2 = native_zero["positions"]["earth-station"]
    if Intercept.position_after(path, 0.0).distance_to(actual_zero) > 0.00005:
        _fail("ephemeris does not match original N43 station coordinate")
        return
    model.advance_orbits(2.75)
    var native_advanced: Dictionary = resolver.positions_from_world(model, 2.75)
    if not native_advanced.get("ok", false) or Intercept.position_after(
            path, 2.75).distance_to(
            native_advanced["positions"]["earth-station"]) > 0.00005:
        _fail("ephemeris and native orbit advancement diverged")
        return
    if JSON.stringify(seed) != original:
        _fail("N43 predictor mutated original frozen Rust seed")
        return

    # Generic parent-relative body metadata: one real physical frame
    # shared by orbit propagation, resolver and trajectory prediction.
    # Never edit or silently reinterpret the original frozen Sol seed.
    var future_seed: Dictionary = seed.duplicate(true)
    for sys in future_seed["worlds"]:
        if str(sys["system"]["id"]) != "system-sol":
            continue
        for body in sys["bodies"]:
            if str(body["id"]) == "luna":
                body["parent_body_id"] = "earth"
                body["satellite_orbit_radius_native"] = (
                    384400.0 / 149597870.7 * 2.0)
    var future_model: RefCounted = WorldModel.new()
    var future_resolver: RefCounted = Resolver.new()
    if not future_model.load_seed(future_seed) or not (
            future_resolver.load_seed(future_seed)):
        _fail("explicit local Moon metadata cannot be read")
        return
    var future_parent: Dictionary = future_resolver.body_universe_position(
        "earth", future_model)
    var future_moon: Dictionary = future_resolver.body_universe_position(
        "luna", future_model)
    if not future_parent.get("ok", false) or not future_moon.get("ok", false):
        _fail("physical Moon/parent coordinates not available")
        return
    var moon_gap: float = (future_moon["position"] as Vector2).distance_to(
        future_parent["position"])
    var local_radius: float = 384400.0 / 149597870.7 * 2.0
    if absf(moon_gap - local_radius) > 0.00005:
        _fail("Moon did not preserve local orbital radius")
        return
    var future_angles: Dictionary = future_model.orbital_snapshot()
    var moon_parts: Array = future_resolver._components_for_body(
        "luna", future_angles, {})
    if moon_parts.size() != 2:
        _fail("Earth + Moon is not a two-component native ephemeris")
        return
    var future_path: Dictionary = {
        "center": Vector2.ZERO, "components": moon_parts}
    if Intercept.position_after(future_path, 0.0).distance_to(
            future_moon["position"]) > 0.00005:
        _fail("Moon parented physical position disagrees with predictor")
        return

    var impossible: Dictionary = Intercept.intercept(Vector2.ZERO,
        0.01, {"center": Vector2.ZERO, "components": [{
            "radius": 2.0, "angle": 0.0, "period": 300.0}]}, 1.0)
    if impossible.get("ok", false):
        _fail("solver invented an impossible short-horizon intercept")
        return
    var fallback: Dictionary = Intercept.aim_point(
        Vector2.ZERO, 0.01, {}, Vector2(8.0, 4.0))
    if fallback.get("prediction_used", true) or (
            fallback.get("point", Vector2.ZERO) != Vector2(8.0, 4.0)):
        _fail("invalid forecast did not preserve original pursuit")
        return

    # Two real N14 ships with identical route, fuel and native speed:
    # one pursues the current moving planet, one intercepts future orbit.
    var chasing: RefCounted = State.new()
    var leading: RefCounted = State.new()
    for pair in [chasing, leading]:
        if not pair.add_ship("courier-1", "courier", "test-faction",
                "test-system", "small"):
            _fail("test fleet bootstrap rejected")
            return
        pair.ships["courier-1"]["location"] = "start"
    var graph: RefCounted = StubGraph.new()
    var chase: RefCounted = Transit.new()
    var lead: RefCounted = Transit.new()
    var basic: Dictionary = {
        "center": Vector2.ZERO, "components": [{
            "radius": 2.0, "angle": 0.0, "period": 300.0
        }]}
    var departure: Dictionary = {"start": Vector2.ZERO,
        "target": Intercept.position_after(basic, 0.0)}
    if not chase.depart(chasing, graph, "courier-1", "target",
            departure, 0, 1.0) or not lead.depart(leading, graph,
            "courier-1", "target", departure, 0, 1.0):
        _fail("N14 physical departures rejected")
        return
    var speed: float = 0.05 * Catalog.effective_speed("courier", "small")
    var chase_arrival: int = -1
    var lead_arrival: int = -1
    for tick in range(1, 190):
        var current_motion: Dictionary = {
            "center": Vector2.ZERO, "components": [{
                "radius": 2.0, "angle": 360.0 * float(tick) / 300.0,
                "period": 300.0
            }]}
        var target: Vector2 = Intercept.position_after(current_motion, 0.0)
        var positions: Dictionary = {"start": Vector2.ZERO, "target": target}
        if chase_arrival < 0:
            var c_before: Vector2 = Vector2(
                float(chasing.ships["courier-1"]["transit"]["position"][0]),
                float(chasing.ships["courier-1"]["transit"]["position"][1]))
            var c_result: String = chase.advance(chasing, "courier-1",
                positions, tick, 1.0)
            if c_result == "arrived":
                if c_before.distance_to(target) > speed + 0.001:
                    _fail("N14 chase teleported to a distant destination")
                    return
                chase_arrival = tick
            elif c_result != "moving":
                _fail("N14 chase failed: " + c_result)
                return
        if lead_arrival < 0:
            var l_before: Vector2 = Vector2(
                float(leading.ships["courier-1"]["transit"]["position"][0]),
                float(leading.ships["courier-1"]["transit"]["position"][1]))
            var l_result: String = lead.advance(leading, "courier-1",
                positions, tick, 1.0, 1, false, current_motion)
            if l_result == "arrived":
                if l_before.distance_to(target) > speed + 0.001:
                    _fail("N14 lead teleported without meeting target")
                    return
                lead_arrival = tick
            elif l_result != "moving":
                _fail("N14 lead failed: " + l_result)
                return
        if chase_arrival >= 0 and lead_arrival >= 0:
            break
    if chase_arrival < 0 or lead_arrival < 0:
        _fail("physical N14 flights did not both finish")
        return
    if lead_arrival >= chase_arrival:
        _fail("lead guidance did not improve moving-target flight: " +
            str(lead_arrival) + " versus " + str(chase_arrival))
        return
    if float(leading.ships["courier-1"]["fuel"]) < 0.0 or (
            float(leading.ships["courier-1"]["fuel"]) < (
            float(chasing.ships["courier-1"]["fuel"]))):
        _fail("real N14 fuel accounting invalid")
        return
    if leading.ships["courier-1"]["transit"] != {} or (
            chasing.ships["courier-1"]["transit"] != {}):
        _fail("N14 arrival did not clear true transit")
        return
    # Short CI cost sample: baseline calculation for one moving target.
    # Not a Windows 50+ systems benchmark; only an order-of-magnitude
    # signal before allowing this feature into the main simulation.
    var bench_start: int = Time.get_ticks_usec()
    var solved: int = 0
    var sample_speed: float = 0.05 * Catalog.effective_speed(
        "courier", "small")
    for _sample in range(500):
        var result: Dictionary = Intercept.aim_point(
            Vector2(0.3, -0.1), sample_speed, basic,
            Intercept.position_after(basic, 0.0))
        if result.get("prediction_used", false):
            solved += 1
    if solved != 500:
        _fail("fast forecast benchmark had missing intercepts")
        return
    var bench_us: int = Time.get_ticks_usec() - bench_start
    print("P2 NATIVE ORBITAL INTERCEPT COST: 500 solves, ",
        bench_us, " usec total, ", float(bench_us) / 500.0,
        " usec/solve on Linux CI")
    print("P2 NATIVE ORBITAL INTERCEPT PASS: lead=", lead_arrival,
        " ticks pursuit=", chase_arrival,
        " ticks; live seed N43 parity, parented Moon, fuel, arrival")
    quit(0)


func _fail(reason: String) -> void:
    push_error("P2 NATIVE ORBITAL INTERCEPT FAIL: " + reason)
    quit(1)
