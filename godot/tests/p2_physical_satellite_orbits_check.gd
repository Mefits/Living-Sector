extends SceneTree
## SystemBalance physical satellites acceptance, real Godot 4.7.2:
## godot --headless --path godot --script res://tests/p2_physical_satellite_orbits_check.gd
const NativeData = preload("res://scripts/native_data.gd")
const WorldModel = preload("res://scripts/sim/world_model.gd")
const N43 = preload("res://scripts/sim/ships/native_location_resolver.gd")
const Intercept = preload("res://scripts/sim/ships/native_orbital_intercept.gd")
const View = preload("res://scripts/star_system_view.gd")
const TickRunner = preload("res://scripts/sim/tick_runner.gd")
const Profiles = preload("res://scripts/sim/orbits/native_satellite_orbit_profiles.gd")

func _initialize() -> void:
    call_deferred("_test")


func _test() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("missing untouched Galaxy 0.6.7 source: " + str(seed["error"]))
        return
    var original_source: String = JSON.stringify(seed)
    var old_fingerprint: String = JSON.stringify(
        [seed["worlds"], seed["factions"]]).sha256_text()
    var frozen_sol: Dictionary = _sol(seed["worlds"])
    if frozen_sol.is_empty():
        _fail("missing frozen Sol")
        return
    var frozen_moon: Dictionary = _body(frozen_sol, "luna")
    if frozen_moon.has("parent_body_id"):
        _fail("frozen Rust source was already modified by the test")
        return

    var model: RefCounted = WorldModel.new()
    var resolver: RefCounted = N43.new()
    if not model.load_seed(seed) or not resolver.load_seed(seed):
        _fail("canonical derived World and N43 resolver rejected Sol")
        return
    if JSON.stringify(seed) != original_source:
        _fail("imported frozen Rust source mutated")
        return
    if model.seed_fingerprint() == old_fingerprint:
        _fail("new physical orbit checkpoint identity not versioned")
        return
    # Never guess which star a fictional moon belongs to. Other
    # frozen systems remain bit-for-bit unchanged by the Sol profile.
    for raw_system in seed["worlds"]:
        if str(raw_system.get("system", {}).get("id", "")) == "system-sol":
            continue
        for raw_body in raw_system.get("bodies", []):
            var imported: Dictionary = model.body_by_id(
                str(raw_body.get("id", "")))
            if imported.get("value", {}) != raw_body:
                _fail("non-Sol native body was rewritten by satellite profile")
                return

    # All-or-nothing guard: a custom Sol with edited Callisto source
    # must not acquire an unrequested physical Luna override.
    var changed_seed: Dictionary = seed.duplicate(true)
    for w in changed_seed["worlds"]:
        if str(w.get("system", {}).get("id", "")) == "system-sol":
            for b in w["bodies"]:
                if str(b.get("id", "")) == "callisto":
                    b["orbit_radius"] = 11.0
    var custom_model: RefCounted = WorldModel.new()
    if not custom_model.load_seed(changed_seed) or (
            custom_model.body_by_id("luna").get("value", {}).has(
            "parent_body_id")):
        _fail("edited Sol unexpectedly acquired a partial moon migration")
        return
    var derived_sol: Dictionary = _sol(model.worlds())
    if derived_sol.is_empty():
        _fail("derived World did not expose Sol")
        return
    var moon: Dictionary = _body(derived_sol, "luna")
    var callisto: Dictionary = _body(derived_sol, "callisto")
    for sample in [
        [moon, "earth", 384400.0, 27.321661],
        [callisto, "jupiter", 1882700.0, 16.689017]
    ]:
        var satellite: Dictionary = sample[0]
        if str(satellite.get("parent_body_id", "")) != sample[1] or (
                str(satellite.get("satellite_profile", "")) != "sol-parented-circular-v1"):
            _fail("canonical real parent is missing")
            return
        var expect_radius: float = (
            float(sample[2]) / Profiles.KM_PER_AU * Profiles.SOL_UNITS_PER_AU)
        var expect_period: float = (
            Profiles.NATIVE_EARTH_YEAR * float(sample[3]) / Profiles.EARTH_YEAR_DAYS)
        if absf(float(satellite["satellite_orbit_radius_native"]) -
                expect_radius) > 0.0000001 or absf(float(
                satellite["satellite_orbit_period_native"]) -
                expect_period) > 0.00001:
            _fail("real moon distance or sidereal period does not match profile")
            return
    if float(moon["orbit_period"]) != 735.0 or (
            float(callisto["orbit_period"]) != 4350.0):
        _fail("Rust original orbit_period overwritten instead of versioned")
        return

    # Both planets retain their native heliocentric orbits. Their moons
    # inherit the parent's moving world position, even after real time.
    var snapshot: Dictionary = model.orbital_snapshot()
    for sample in [["luna", "earth", 384400.0],
            ["callisto", "jupiter", 1882700.0]]:
        var child_id: String = sample[0]
        var parent_id: String = sample[1]
        var period_radius: float = (
            float(sample[2]) / Profiles.KM_PER_AU * Profiles.SOL_UNITS_PER_AU)
        var parent: Dictionary = resolver.body_universe_position(
            parent_id, model)
        var child: Dictionary = resolver.body_universe_position(
            child_id, model)
        if not parent.get("ok", false) or not child.get("ok", false):
            _fail("N43 native physical body positions unavailable")
            return
        if absf((child["position"] as Vector2).distance_to(
                parent["position"]) - period_radius) > 0.00001:
            _fail("N43 moon is not centered on its actual planet")
            return
        var orbits: Array = resolver._components_for_body(
            child_id, snapshot, {})
        if orbits.size() != 2:
            _fail("native moon requires parent and local trajectory")
            return
        var trajectory: Dictionary = {
            "center": Vector2.ZERO, "components": orbits}
        if Intercept.position_after(trajectory, 0.0).distance_to(
                child["position"]) > 0.00001:
            _fail("N14 physical prediction and current N43 moon disagree")
            return

    var future: float = 17.5
    var moon_before: float = float(snapshot["luna"])
    model.advance_orbits(future)
    var future_angles: Dictionary = model.orbital_snapshot()
    if absf(float(future_angles["luna"]) -
            fposmod(moon_before + future *
                360.0 / float(moon["satellite_orbit_period_native"]), 360.0)
            ) > 0.00005:
        _fail("World clock did not advance Moon at local sidereal period")
        return
    for sample in [["luna", "earth", 384400.0],
            ["callisto", "jupiter", 1882700.0]]:
        var bid: String = sample[0]
        var parent_id: String = sample[1]
        var parts: Array = resolver._components_for_body(
            bid, snapshot, {})
        var forecast: Dictionary = {
            "center": Vector2.ZERO, "components": parts}
        var actual: Dictionary = resolver.body_universe_position(bid, model)
        var parent: Dictionary = resolver.body_universe_position(parent_id, model)
        if not actual.get("ok", false) or (
                not parent.get("ok", false)):
            _fail("Moon lost native position after orbit advancement")
            return
        if Intercept.position_after(forecast, future).distance_to(
                actual["position"]) > 0.00005:
            _fail("N43 real movement and N14 future interception diverged")
            return
        var r: float = (
            float(sample[2]) / Profiles.KM_PER_AU * Profiles.SOL_UNITS_PER_AU)
        if absf((actual["position"] as Vector2).distance_to(
                parent["position"]) - r) > 0.00001:
            _fail("Moon lost its planet during orbital advancement")
            return

    # N38 compatibility: explicit rejection of pre-migration geometry
    # instead of a silent switch of coordinate frames mid-flight.
    var runner: RefCounted = TickRunner.new()
    if not runner.start_from_seed(seed):
        _fail("real canonical TickRunner cannot load derived Sol")
        return
    var cp: Dictionary = runner.checkpoint()
    var valid_snapshot: String = JSON.stringify(cp)
    cp["seed_fingerprint"] = old_fingerprint
    if runner.restore_checkpoint(cp, seed):
        _fail("old heliocentric checkpoint was silently reinterpreted")
        return
    if runner.tick_count != 0 or runner.world.seed_fingerprint() != (
            model.seed_fingerprint()):
        _fail("rejected old save altered live native World")
        return
    if not runner.restore_checkpoint(JSON.parse_string(valid_snapshot), seed):
        _fail("new physical orbit checkpoint fails restart")
        return

    # A real navigable Moon facility (only in a fixture) receives N43
    # coordinates anchored on physical Luna, not on legacy solar orbit.
    var fixture: Dictionary = seed.duplicate(true)
    for w in fixture["worlds"]:
        if str(w.get("system", {}).get("id", "")) == "system-sol":
            w["facilities"].append({
                "id": "fixture-lunar-orbit", "location": "fixture-lunar-dock",
                "body": "luna", "docking_capacity": 1
            })
    var fixture_model: RefCounted = WorldModel.new()
    var fixture_resolver: RefCounted = N43.new()
    if not fixture_model.load_seed(fixture) or not (
            fixture_resolver.load_seed(fixture)):
        _fail("real moon facility fixture rejected")
        return
    var station_coords: Dictionary = fixture_resolver.positions_from_world(
        fixture_model, 0.0)
    var station_traj: Dictionary = fixture_resolver.ephemeris_for_location(
        "fixture-lunar-dock", fixture_model, 0.0)
    if not station_coords.get("ok", false) or not (
            station_traj.get("ok", false)):
        _fail("lunar station cannot resolve physical navigation")
        return
    if Intercept.position_after(station_traj["trajectory"], 0.0).distance_to(
            station_coords["positions"]["fixture-lunar-dock"]) > 0.00005:
        _fail("lunar docking position differs from N14 trajectory")
        return
    if station_traj["trajectory"]["components"].size() != 3:
        _fail("Moon docking station did not inherit Moon+Earth+station orbits")
        return

    # The very same extended model drives the existing UI body hierarchy.
    var view: Control = View.new()
    root.add_child(view)
    view.size = Vector2(1200, 900)
    view.call("set_world", derived_sol)
    var parent_view: Dictionary = view.call(
        "_known_moon_parent", moon)
    if str(parent_view.get("id", "")) != "earth":
        _fail("rendered Moon parent not equal to physical parent")
        return
    var local_screen_radius: float = float(view.call(
        "_satellite_orbit_native_radius", moon))
    if absf(local_screen_radius - float(
            moon["satellite_orbit_radius_native"])) > 0.0000001:
        _fail("UI Moon radius does not come from physical World metadata")
        return
    view.queue_free()

    if JSON.stringify(seed) != original_source:
        _fail("input frozen files changed during the native orbital test")
        return
    print("P2 PHYSICAL SATELLITES PASS: Moon->Earth, Callisto->Jupiter, ",
        "authentic local radii/periods, N43=N14, lunar station, ",
        "versioned safe save rejection, unchanged Rust source")
    quit(0)


static func _sol(worlds: Array) -> Dictionary:
    for w in worlds:
        if str(w.get("system", {}).get("id", "")) == "system-sol":
            return w
    return {}


static func _body(world: Dictionary, id: String) -> Dictionary:
    for b in world.get("bodies", []):
        if str(b.get("id", "")) == id:
            return b
    return {}


func _fail(reason: String) -> void:
    push_error("P2 PHYSICAL SATELLITES FAIL: " + reason)
    quit(1)
