extends SceneTree
## SystemBalance local-station + real solar detour acceptance.
## Executes actual N43 geometry and N14 ship transit with paid fuel.
const NativeData = preload("res://scripts/native_data.gd")
const WorldModel = preload("res://scripts/sim/world_model.gd")
const Resolver = preload("res://scripts/sim/ships/native_location_resolver.gd")
const Intercept = preload("res://scripts/sim/ships/native_orbital_intercept.gd")
const Avoidance = preload("res://scripts/sim/ships/native_avoidance.gd")
const Transit = preload("res://scripts/sim/ship_transit.gd")
const State = preload("res://scripts/sim/ship_state.gd")
const Catalog = preload("res://scripts/sim/ship_catalog.gd")

class TestGraph:
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
        _fail("source seed unavailable")
        return
    var original: String = JSON.stringify(seed)
    var world: RefCounted = WorldModel.new()
    var resolver: RefCounted = Resolver.new()
    if not world.load_seed(seed) or not resolver.load_seed(seed):
        _fail("N43 source world startup")
        return
    var earth: Vector2 = resolver.body_universe_position(
        "earth", world)["position"]
    var stations: Dictionary = resolver.positions_from_world(world, 0.0)
    var forecast: Dictionary = resolver.ephemeris_for_location(
        "earth-station", world, 0.0)
    var station: Vector2 = stations.get("positions", {}).get(
        "earth-station", Vector2.ZERO)
    var radius: float = resolver.station_radius_for_location(
        "earth-station")
    var expected: float = (6371.0 + 800.0) * 2.0 / 149597870.7
    if not stations.get("ok", false) or not forecast.get("ok", false):
        _fail("native station position missing")
        return
    if absf(radius - expected) > 0.00000001 or absf(
            earth.distance_to(station) - expected) > 0.000003:
        _fail("Earth station not in physical 800 km local orbit")
        return
    if Intercept.position_after(forecast["trajectory"], 0.0
            ).distance_to(station) > 0.000003:
        _fail("Earth station N43 position and N14 future mismatch")
        return
    if resolver.arrival_tolerance_for_location("earth-station") >= 0.01:
        _fail("old Rust .01 arrival bubble still active in local Sol")
        return
    if resolver.station_radius_for_location("alpha-station") != 0.55:
        _fail("unverified non-Sol system silently rescaled")
        return
    if not (world.system_by_id("system-sol").has(
            "navigation_geometry_profile")):
        _fail("new physical navigation lacks checkpoint geometry version")
        return

    var danger: Dictionary = resolver.verified_solar_exclusion("system-sol")
    if danger.is_empty() or danger.get("center") != Vector2.ZERO:
        _fail("verified Sun exclusion unavailable")
        return
    var start: Vector2 = Vector2(-2.0, 0.0)
    var target: Vector2 = Vector2(2.0, 0.0)
    var clearance: float = float(danger["radius"])
    if not Avoidance.segment_crosses(start, target,
            Vector2.ZERO, clearance):
        _fail("direct Sun crossing was not identified")
        return
    var route: Dictionary = Avoidance.plan(
        start, target, Vector2.ZERO, clearance)
    if not route.get("ok", false) or not Avoidance.valid_stored_points(
            route.get("points", null)) or (
            (route["points"] as Array).size() < 2):
        _fail("bounded physical solar arc could not be planned")
        return
    var last: Vector2 = start
    for arr in route["points"]:
        var point: Vector2 = Vector2(float(arr[0]), float(arr[1]))
        if Avoidance.segment_crosses(last, point,
                Vector2.ZERO, clearance):
            _fail("planned solar arc crosses danger zone")
            return
        last = point
    if Avoidance.segment_crosses(last, target,
            Vector2.ZERO, clearance):
        _fail("planned final approach crosses danger zone")
        return

    var states: RefCounted = State.new()
    if not states.add_ship("courier", "courier", "test-faction", "system-sol"):
        _fail("N14 courier fixture missing")
        return
    states.ships["courier"]["location"] = "start"
    var motion: RefCounted = Transit.new()
    var positions: Dictionary = {"start": start, "target": target}
    if not motion.depart(states, TestGraph.new(),
            "courier", "target", positions, 0, 1.0):
        _fail("canonical N14 directed launch failed")
        return
    var before_fuel: float = float(states.ships["courier"]["fuel"])
    var cost: float = float(Catalog.spec("courier")["fuel_consumption_base"])
    var velocity: float = Transit.BASE_VELOCITY * (
        Catalog.effective_speed("courier", "small"))
    var paid_ticks: int = 0
    var arrival_tick: int = -1
    for tick in range(1, 160):
        var transit: Dictionary = states.ships["courier"]["transit"]
        if transit.is_empty():
            _fail("route vanished before validated arrival")
            return
        var old: Vector2 = Vector2(float(transit["position"][0]),
            float(transit["position"][1]))
        var outcome: String = motion.advance(states, "courier", positions,
            tick, 1.0, 1, false, {}, 0.00001, danger)
        if not (outcome in ["moving", "arrived"]):
            _fail("unverified navigation outcome: " + outcome)
            return
        paid_ticks += 1
        if outcome == "arrived":
            if old.distance_to(target) > velocity + 0.00001:
                _fail("solar detour teleport during arrival")
                return
            arrival_tick = tick
            break
        var updated: Dictionary = states.ships["courier"]["transit"]
        var current: Vector2 = Vector2(float(updated["position"][0]),
            float(updated["position"][1]))
        if old.distance_to(current) > velocity + 0.00001:
            _fail("N14 detour moved faster than paid ship speed")
            return
        if Avoidance.segment_crosses(old, current,
                Vector2.ZERO, clearance):
            _fail("canonical ship crossed Sun despite stored route")
            return
        if tick == 1:
            if not updated.has("navigation_waypoints"):
                _fail("detour not persisted in native transit")
                return
            var saved: Array = states.snapshot()
            var resumed: RefCounted = State.new()
            if not resumed.restore(saved) or resumed.ships[
                    "courier"]["transit"].get(
                    "navigation_waypoints", []) != updated[
                    "navigation_waypoints"]:
                _fail("N38/N39 would drop canonical solar waypoints")
                return
    if arrival_tick < 0 or states.ships["courier"]["location"] != (
            "target") or not states.ships["courier"]["transit"].is_empty():
        _fail("physical detour never completed destination")
        return
    if absf(float(states.ships["courier"]["fuel"]) -
            (before_fuel - cost * float(paid_ticks))) > 0.0001:
        _fail("detour fuel was not charged for every moving tick")
        return
    if JSON.stringify(seed) != original:
        _fail("source Galaxy seed was modified")
        return
    print("P2 NATIVE NAVIGATION PASS: station=", expected,
        " vs old 0.55 native; real N14 Sun detour ", arrival_tick,
        " paid ticks; 1 N39 transit, no cut-through or teleport")
    quit(0)


func _fail(reason: String) -> void:
    push_error("P2 NATIVE NAVIGATION FAIL: " + reason)
    quit(1)
