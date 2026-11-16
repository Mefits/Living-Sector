extends SceneTree
## 500 genuine ShipTransit instances with physically committed route state,
## but synthetic fleet fixture: NOT a full N39/N9/AI economic stress test.
## Both solar detours and open-space cached lead are exercised concurrently.
const Transit = preload("res://scripts/sim/ship_transit.gd")
const NativeData = preload("res://scripts/native_data.gd")
const Model = preload("res://scripts/sim/world_model.gd")
const Resolver = preload("res://scripts/sim/ships/native_location_resolver.gd")
const State = preload("res://scripts/sim/ship_state.gd")
const Avoidance = preload("res://scripts/sim/ships/native_avoidance.gd")
const Intercept = preload("res://scripts/sim/ships/native_orbital_intercept.gd")
const COUNT: int = 500
const STEPS: int = 9

class Graph:
    extends RefCounted
    func outgoing(origin: String) -> Array:
        return [{"from": origin, "to": "target"}]


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    var model: RefCounted = Model.new()
    var resolver: RefCounted = Resolver.new()
    if seed.has("error") or not model.load_seed(seed) or (
            not resolver.load_seed(seed)):
        _fail("cannot load real Sol native obstacles")
        return
    var planets: Array = resolver.verified_planet_obstacles(
        "system-sol", model)
    if planets.size() < 7 or planets.size() > 16:
        _fail("bounded real planetary collision registry unavailable")
        return
    var state: RefCounted = State.new()
    var motion: RefCounted = Transit.new()
    var start_locations: Dictionary = {}
    var sky: Dictionary = {"center": Vector2.ZERO, "components": [{
        "radius": 2.0, "angle": 0.0, "period": 700.0
    }]}
    var goal: Vector2 = Intercept.position_after(sky, 0.0)
    var positions: Dictionary = {"target": goal}
    for i in range(COUNT):
        var id: String = "vessel-%04d" % i
        var start: String = "start-%04d" % i
        if not state.add_ship(id, "courier", "test-faction",
                "system-sol", "small"):
            _fail("cannot instantiate synthetic native transit " + id)
            return
        state.ships[id]["location"] = start
        # Two corridors: one requires a solar detour, the other is clear.
        var xy: Vector2 = (
            Vector2(-2.0 - float(i % 13) * 0.02,
                float(i % 15 - 7) * 0.015)
            if i < COUNT / 2 else Vector2(
                1.0 + float(i % 13) * 0.01,
                float(i % 15 - 7) * 0.015))
        positions[start] = xy
        start_locations[id] = start
    var graph: RefCounted = Graph.new()
    for id in start_locations:
        if not motion.depart(state, graph, str(id), "target",
                positions, 0, 1.0):
            _fail("synthetic N14 departure refused: " + str(id))
            return

    var star: Dictionary = {"center": Vector2.ZERO, "radius": 0.20}
    var elapsed: Array[int] = []
    var waypoint_ships: int = 0
    var lead_ships: int = 0
    var start_fuel: Dictionary = {}
    for id in state.ships:
        start_fuel[id] = float(state.ships[id]["fuel"])
    for tick in range(1, STEPS + 1):
        sky["components"][0]["angle"] = (
            float(tick) * 360.0 / 700.0)
        positions["target"] = Intercept.position_after(sky, 0.0)
        var started: int = Time.get_ticks_usec()
        for id in state.ships:
            var before: Dictionary = state.ships[id]["transit"]
            var p: Vector2 = Vector2(float(before["position"][0]),
                float(before["position"][1]))
            # The two corridors must stress different code paths.
            # The left ships chase the CURRENT real target and require
            # star avoidance; right ships use predictive N14 lead.
            var use_forecast: bool = int(str(id).substr(7)) >= COUNT / 2
            var forecast: Dictionary = sky if use_forecast else {}
            var outcome: String = motion.advance(state, str(id),
                positions, tick, 1.0, 1, false, forecast, 0.00001, star,
                planets, "earth")
            if outcome != "moving":
                _fail("500 native flights returned " + outcome +
                    " for " + str(id) + " on tick " + str(tick))
                return
            var after: Dictionary = state.ships[id]["transit"]
            var moved: Vector2 = Vector2(float(after["position"][0]),
                float(after["position"][1]))
            if Avoidance.segment_crosses(p, moved, Vector2.ZERO, 0.20):
                _fail("500-ship native collision geometry was bypassed")
                return
            if tick == 1:
                if after.has("navigation_waypoints"):
                    waypoint_ships += 1
                elif after.has("cached_lead_point"):
                    lead_ships += 1
            if tick == 3 and int(id.substr(7)) >= COUNT / 2:
                # Open-space ship must reuse, not recompute the 24-step
                # bisection on every active fired N14 tick.
                if int(after.get("lead_replan_tick", 0)) != (
                        1 + Transit.LEAD_REPLAN_TICKS):
                    _fail("cached N14 lead recalculated on every tick")
                    return
        elapsed.append(Time.get_ticks_usec() - started)
    if waypoint_ships < 100 or lead_ships < 100:
        _fail("500-ship fixture did not test both navigation corridors: detour=" +
            str(waypoint_ships) + " lead=" + str(lead_ships))
        return
    var full: Array = state.snapshot()
    var recovered: RefCounted = State.new()
    if not recovered.restore(full) or recovered.ships.size() != COUNT:
        _fail("canonical 500 ship waypoint/cursor reload rejected")
        return
    for id in state.ships:
        if recovered.ships[id]["transit"] != (
                state.ships[id]["transit"]):
            _fail("N14 500-ship saved route state changed")
            return
        if float(state.ships[id]["fuel"]) >= float(start_fuel[id]):
            _fail("500-ship physical route consumed no fuel")
            return
    var peak: int = elapsed.max()
    var sorted: Array[int] = elapsed.duplicate()
    sorted.sort()
    var p95: int = sorted[mini(sorted.size() - 1, ceili(
        float(sorted.size()) * 0.95) - 1)]
    print("P2 N14 NAV 500 COST: ", COUNT, " genuine transit steps x ",
        STEPS, "; peak=", peak, " us; p95=", p95, " us;",
        " star-detours=", waypoint_ships, "; open-lead=", lead_ships,
        "; real-planet-obstacles=", planets.size())
    print("P2 N14 NAV 500 PASS: bounded solar arcs and cached",
        " predictions saved with 500 N14 ships, no collision, real fuel")
    quit(0)


func _fail(reason: String) -> void:
    push_error("P2 N14 NAV 500 FAIL: " + reason)
    quit(1)
