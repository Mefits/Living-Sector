extends SceneTree
## Regression: original SystemBalance parented physical moon orbit stays
## identical, even when HUD's 140% UI scale shrinks logical viewport.
const Data = preload("res://scripts/native_data.gd")
const Model = preload("res://scripts/sim/world_model.gd")
const View = preload("res://scripts/star_system_view.gd")
const SolOrbits = preload("res://scripts/sim/orbits/native_satellite_orbit_profiles.gd")

func _initialize() -> void:
    var seed: Dictionary = Data.load_current_world()
    assert(not seed.has("error"))
    var source_before: String = JSON.stringify(seed)
    var model: RefCounted = Model.new()
    assert(model.load_seed(seed))
    var sol: Dictionary = model.system_by_id("system-sol")
    var earth: Dictionary = {}
    var luna: Dictionary = {}
    for body in sol.get("bodies", []):
        if str(body.get("id", "")) == "earth":
            earth = body
        elif str(body.get("id", "")) == "luna":
            luna = body
    assert(not earth.is_empty() and not luna.is_empty())
    assert(str(luna.get("parent_body_id", "")) == "earth")
    var local_radius: float = float(luna.get(
        "satellite_orbit_radius_native", 0.0))
    assert(absf(local_radius - 384400.0 / SolOrbits.KM_PER_AU *
        SolOrbits.SOL_UNITS_PER_AU) < 0.000001)
    # Compare physical screen pixels, not Godot logical Control pixels.
    # The established SystemBalance 100%-UI view is the canonical size:
    # changing only Windows UI scale must not resize planets or Luna's ring.
    var view: Control = View.new()
    var physical_size := Vector2(1000, 740)
    view.size = physical_size
    view.set_world(sol)
    view.set("_zoom", 85.0)
    view.set("_focused_body_id", "earth")
    var base_orbit: float = float(view.call(
        "_satellite_orbit_radius", luna, earth, float(
            view.call("_orbit_scale"))))
    var expected_separation: float = pow(local_radius,
        View.SATELLITE_COMPRESSION) * float(view.call(
            "_orbit_scale")) * 85.0
    assert(is_equal_approx(base_orbit, expected_separation))
    var earth_size: float = float(view.call("_body_size", earth))
    var moon_size: float = float(view.call("_body_size", luna))
    var physical_ratio: float = base_orbit / earth_size
    for ui_scale in [1.25, 1.4, 1.6, 1.8, 2.0]:
        view.size = physical_size / ui_scale
        view.set_ui_viewport_scale(ui_scale)
        var orbital_radius: float = float(view.call(
            "_satellite_orbit_radius", luna, earth, float(
                view.call("_orbit_scale")))) * ui_scale
        var planet_radius: float = float(view.call(
            "_body_size", earth)) * ui_scale
        var luna_radius: float = float(view.call(
            "_body_size", luna)) * ui_scale
        assert(absf(orbital_radius / base_orbit - 1.0) < 0.012)
        assert(absf(planet_radius / earth_size - 1.0) < 0.012)
        assert(absf(luna_radius / moon_size - 1.0) < 0.012)
        assert(absf(orbital_radius / planet_radius -
            physical_ratio) < 0.012)
        # Double-click focus also targets the original physical globe size.
        assert(view.focus_body("earth"))
        var focus_zoom: float = float(view.get("_focus_zoom_target"))
        var focus_radius: float = float(view.call(
            "_body_size_at_zoom", earth, focus_zoom)) * ui_scale
        assert(absf(focus_radius - View.FOCUS_GLOBE_RADIUS) < 1.5)
    view.set_ui_viewport_scale(1.0)
    view.size = physical_size
    view.free()
    assert(JSON.stringify(seed) == source_before)
    print("SOL_MOON_CLOSEUP_LOD_PASS")
    quit()
