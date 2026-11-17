extends SceneTree
## One Sol-only slow/stable station phase, native N43=N14 docking and UI LOD.
## No World, N39, N140, worker or other-system mutation.
const NativeData = preload("res://scripts/native_data.gd")
const WorldModel = preload("res://scripts/sim/world_model.gd")
const N43 = preload("res://scripts/sim/ships/native_location_resolver.gd")
const Profiles = preload("res://scripts/sim/orbits/native_satellite_orbit_profiles.gd")
const Intercept = preload("res://scripts/sim/ships/native_orbital_intercept.gd")
const StarView = preload("res://scripts/star_system_view.gd")


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("frozen seed missing")
        return
    var source: String = JSON.stringify(seed)
    var model: RefCounted = WorldModel.new()
    var resolver: RefCounted = N43.new()
    if not model.load_seed(seed) or not resolver.load_seed(seed):
        _fail("derived canonical Sol cannot load")
        return
    var expected_radius: float = (6371.0 + 800.0) * (
        2.0 / Profiles.KM_PER_AU)
    if absf(resolver.station_radius_for_location("earth-station") -
            expected_radius) > 0.000000001:
        _fail("actual Sol station altitude is not 800 km")
        return
    if resolver.station_period_for_location("earth-station") != (
            Profiles.STATION_ORBIT_PERIOD_NATIVE) or (
            Profiles.STATION_ORBIT_PERIOD_NATIVE != 24000.0):
        _fail("native N43 Sol station period was not slowed 3x")
        return
    if resolver.station_period_for_location("alpha-station") != (
            N43.FACILITY_ORBIT_PERIOD) or resolver.station_radius_for_location(
            "alpha-station") != 0.55:
        _fail("unverified non-Sol station physics was changed")
        return
    if str(model.system_by_id("system-sol").get(
            "navigation_geometry_profile", "")) != (
            Profiles.NAVIGATION_GEOMETRY_VERSION):
        _fail("save fingerprint did not version the changed orbit")
        return

    for time in [0.0, 85.0, 175.0, 12000.0, 24000.0]:
        var snapshot: Dictionary = resolver.positions_from_world(model, time)
        var forecast: Dictionary = resolver.ephemeris_for_location(
            "earth-station", model, time)
        if not snapshot.get("ok", false) or not forecast.get("ok", false):
            _fail("canonical N43 positions/ephemerides missing")
            return
        var parts: Array = forecast["trajectory"]["components"]
        if absf(float(parts.back()["period"]) -
                Profiles.STATION_ORBIT_PERIOD_NATIVE) > 0.000001:
            _fail("N14 is targeting a different station clock")
            return
        var predicted: Vector2 = Intercept.position_after(
            forecast["trajectory"], 0.0)
        var real: Vector2 = snapshot["positions"]["earth-station"]
        if predicted.distance_to(real) > 0.000002:
            _fail("physical arrival and predictive target diverge")
            return

    var view: Control = StarView.new()
    root.add_child(view)
    view.size = Vector2(1200, 800)
    var sol: Dictionary = model.system_by_id("system-sol")
    view.set_world(sol)
    view.set_native_station_time(60.0)
    # Release initial easing so subsequent snapshot starts at an exact
    # nonzero phase. This tests the formerly double-converted angle.
    view.set("_station_time_started_usec", -1)
    var frozen_deg: float = float(view.call(
        "_visual_station_time", Time.get_ticks_usec()))
    var expected_from: float = 60.0 * 360.0 / (
        Profiles.STATION_ORBIT_PERIOD_NATIVE)
    if absf(frozen_deg - expected_from) > 0.00001:
        _fail("native station time is not exactly one phase angle")
        return
    view.set_native_station_time(120.0)
    var from_degrees: float = float(view.get("_station_phase_from_deg"))
    if absf(from_degrees - expected_from) > 0.00001:
        _fail("old displayed phase converted twice between samples")
        return
    var start_usec: int = int(view.get("_station_time_started_usec"))
    var duration_usec: int = int(view.get("_station_time_duration_usec"))
    var mid: float = float(view.call("_visual_station_time",
        start_usec + duration_usec / 2))
    var expected_mid: float = 90.0 * 360.0 / (
        Profiles.STATION_ORBIT_PERIOD_NATIVE)
    if absf(mid - expected_mid) > 0.00002:
        _fail("station orbit phase jitters across GUI frames")
        return
    var end_phase: float = float(view.call("_visual_station_time",
        start_usec + duration_usec))
    if absf(end_phase - 120.0 * 360.0 / (
            Profiles.STATION_ORBIT_PERIOD_NATIVE)) > 0.00002:
        _fail("station GUI never reached the actual N43 phase")
        return

    view.set("_station_time_started_usec", -1)
    view.set("_zoom", 1.0)
    view.queue_redraw()
    await process_frame
    await process_frame
    var far_pin: Dictionary = _station_pin(view)
    if far_pin.is_empty() or absf(float(far_pin["hit_radius"]) -
            15.0) > 0.05:
        _fail("distant orbital station LOD/click size incorrect")
        return
    view.set("_zoom", 52.0)
    view.queue_redraw()
    await process_frame
    await process_frame
    var near_pin: Dictionary = _station_pin(view)
    if near_pin.is_empty() or absf(float(near_pin["hit_radius"]) -
            24.0) > 0.05:
        _fail("station near-camera mouse target not enlarged")
        return
    var earth: Dictionary = model.body_by_id("earth").get("value", {})
    var body_px: Vector2 = view.call(
        "_body_position", earth, float(view.call("_orbit_scale")))
    var body_radius: float = float(view.call("_body_size", earth))
    var station_distance: float = (
        near_pin["position"] as Vector2).distance_to(body_px)
    if station_distance < body_radius + 38.0:
        _fail("station close-up visual orbit still at old 20px gap")
        return
    view.queue_free()
    if JSON.stringify(seed) != source:
        _fail("Sol visual tuning mutated frozen Rust source")
        return
    print("P2 SLOW SOL STATION PASS: altitude=800km, period=24000,",
        " phase interpolated once, near mouse radius=24px,",
        " zoomed orbital gap>=40px, original N14/N43 target parity")
    quit(0)


func _station_pin(view: Control) -> Dictionary:
    for pin in view.get("_facility_pins"):
        if str(pin.get("id", "")) == "facility-earth-station":
            return pin
    return {}


func _fail(reason: String) -> void:
    push_error("P2 SLOW SOL STATION FAIL: " + reason)
    quit(1)
