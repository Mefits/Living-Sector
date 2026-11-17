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
    var view: Control = View.new()
    view.size = Vector2(1000, 740)
    view.set_world(sol)
    view.set("_zoom", 85.0)
    view.set("_focused_body_id", "earth")
    var original_separation: float = float(view.call(
        "_satellite_orbit_radius", luna, earth, float(
            view.call("_orbit_scale"))))
    # Same precise SystemBalance visual formula, no arbitrary moon ratio.
    var expected_separation: float = pow(local_radius,
        View.SATELLITE_COMPRESSION) * float(
            view.call("_orbit_scale")) * 85.0
    assert(is_equal_approx(original_separation, expected_separation))
    var original_size: float = float(view.call("_body_size", luna))
    var expected_size: float = float(view.call(
        "_overview_body_radius", luna)) * float(view.call(
        "_body_size_at_zoom", earth, 85.0)) / float(
        view.call("_overview_body_radius", earth))
    assert(is_equal_approx(original_size, expected_size))
    # Global 140% changes Control.size in logical units; compensate
    # *only* the camera viewport scale, without touching moon mechanics.
    view.size = Vector2(1000.0 / 1.4, 740.0 / 1.4)
    view.set_ui_viewport_scale(1.4)
    var ui140_separation: float = float(view.call(
        "_satellite_orbit_radius", luna, earth, float(
            view.call("_orbit_scale"))))
    assert(absf(ui140_separation / original_separation - 1.0) < 0.012)
    assert(is_equal_approx(float(view.call("_body_size", luna)),
        original_size))
    # At overview scale, preserve the original responsive map fitting.
    view.set("_zoom", 1.0)
    var fit_140: float = float(view.call("_orbit_scale"))
    view.set_ui_viewport_scale(1.0)
    var fit_100: float = float(view.call("_orbit_scale"))
    assert(is_equal_approx(fit_140, fit_100))
    view.free()
    assert(JSON.stringify(seed) == source_before)
    print("SOL_MOON_CLOSEUP_LOD_PASS")
    quit()
