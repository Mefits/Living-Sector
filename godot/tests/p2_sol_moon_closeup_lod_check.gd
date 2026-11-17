extends SceneTree
## Regression for Sol moon close-up map LOD, NOT physical ephemeris.
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
    assert(absf(float(luna.get("satellite_orbit_radius_native", 0.0))
        - 384400.0 / SolOrbits.KM_PER_AU * SolOrbits.SOL_UNITS_PER_AU)
        < 0.000001)
    var view: Control = View.new()
    view.size = Vector2(1000, 740)
    view.set_world(sol)
    # Orbit overview stays governed by original SystemBalance LOD.
    view.set("_zoom", 1.0)
    var overview_radius: float = float(view.call("_body_size", luna))
    assert(absf(overview_radius - 4.0) < 0.01)
    var orbit_overview: float = float(view.call("_satellite_orbit_radius",
        luna, earth, float(view.call("_orbit_scale"))))
    view.set("_focused_body_id", "earth")
    view.set("_zoom", 85.0)
    var earth_radius: float = float(view.call("_body_size", earth))
    var luna_radius: float = float(view.call("_body_size", luna))
    var ratio: float = float(SolOrbits.SOL_BODY_RADII_KM["luna"]) / float(
        SolOrbits.SOL_BODY_RADII_KM["earth"])
    assert(earth_radius > 90.0)
    assert(absf(luna_radius / earth_radius - ratio) < 0.012)
    var separation: float = float(view.call("_satellite_orbit_radius",
        luna, earth, float(view.call("_orbit_scale"))))
    assert(separation >= earth_radius * 3.7)
    # The relative displayed moon moves farther from Earth at close zoom.
    assert(separation > orbit_overview)
    # When not following Earth, original system-map icon sizing is retained.
    view.set("_focused_body_id", "")
    assert(float(view.call("_body_size", luna)) > luna_radius * 1.7)
    view.free()
    assert(JSON.stringify(seed) == source_before)
    print("SOL_MOON_CLOSEUP_LOD_PASS")
    quit()
