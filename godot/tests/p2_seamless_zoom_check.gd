extends SceneTree
## UI-only acceptance: run with
## godot --headless --path godot --script res://tests/p2_seamless_zoom_check.gd
const NativeData = preload("res://scripts/native_data.gd")
const StarSystemView = preload("res://scripts/star_system_view.gd")

func _initialize() -> void:
    call_deferred("_check")


func _check() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("original seed not available: " + str(seed["error"]))
        return
    var sol: Dictionary = {}
    for world in seed.get("worlds", []):
        if str(world.get("system", {}).get("id", "")) == "system-sol":
            sol = world
            break
    if sol.is_empty():
        _fail("missing frozen Sol world")
        return
    var planet: Dictionary = {}
    for body in sol.get("bodies", []):
        if str(body.get("type", "")) == "planet":
            planet = body
            break
    if planet.is_empty():
        _fail("no authentic Sol planet")
        return

    var before: String = JSON.stringify(sol)
    var view: Control = StarSystemView.new()
    root.add_child(view)
    view.size = Vector2(1000.0, 750.0)
    view.call("set_world", sol)
    var initial_zoom: float = float(view.get("_zoom"))
    view.call("_zoom_at", Vector2(300.0, 280.0), 16.0)
    for i in range(120):
        view.call("_process", 1.0 / 60.0)
    if float(view.get("_zoom")) < 15.0:
        _fail("wheel did not continuously zoom same orbital camera")
        return
    if view.has_method("_draw_body_focus"):
        _fail("legacy alternate globe renderer still active")
        return

    if not bool(view.call("focus_body", str(planet["id"]))):
        _fail("failed to focus real planet")
        return
    for i in range(120):
        view.call("_process", 1.0 / 60.0)
    var detail_radius: float = float(view.call("_body_size", planet))
    if detail_radius < 145.0 or not bool(view.call("is_body_focused")):
        _fail("focus did not enlarge actual orbital planet")
        return

    view.call("unfocus_body")
    for i in range(120):
        view.call("_process", 1.0 / 60.0)
    if absf(float(view.get("_zoom")) - initial_zoom) > 0.02:
        _fail("camera failed to return to orbital scale")
        return
    if bool(view.call("is_body_focused")):
        _fail("return left planet focus active")
        return
    if JSON.stringify(sol) != before:
        _fail("camera mutation changed the frozen system")
        return

    # Auto-follow must engage on wheel detail scale, without a second
    # scene or requiring a double click. Simulate a real visible pin.
    view.call("set_world", sol)
    view.set("_draw_body_positions", {})
    var earth_for_follow: Dictionary = {}
    for value in sol.get("bodies", []):
        if str(value.get("id", "")) == "earth":
            earth_for_follow = value
            break
    if earth_for_follow.is_empty():
        _fail("Earth missing for camera follow check")
        return
    var origin: Vector2 = view.call("_body_position", earth_for_follow,
        float(view.call("_orbit_scale")))
    view.set("_body_pins", [{"body": earth_for_follow, "position": origin,
        "hit_radius": 25.0}])
    view.call("_zoom_at", origin, 32.0)
    for i in range(120):
        view.call("_process", 1.0 / 60.0)
    if not bool(view.call("is_body_focused")):
        _fail("wheel detail did not auto-follow its real target")
        return
    var initial_centered: Vector2 = view.call("_body_position",
        earth_for_follow, float(view.call("_orbit_scale")))
    if initial_centered.distance_to(view.size * 0.5) > 2.0:
        _fail("auto-follow did not converge to planet center")
        return

    # A physically different source angle should move the body, but not
    # eject the focused planet from the viewport at any simulation speed.
    var rotated: Dictionary = sol.duplicate(true)
    for updated in rotated.get("bodies", []):
        if str(updated.get("id", "")) == "earth":
            updated["current_angle"] = fposmod(
                float(updated.get("current_angle", 0.0)) + 90.0, 360.0)
    view.call("update_world", rotated)
    view.set("_body_motion_from", {})
    for i in range(12):
        view.call("_process", 1.0 / 60.0)
    view.set("_draw_body_positions", {})
    var focused_earth: Dictionary = (
        view.get("_body_index") as Dictionary).get("earth", {})
    var moved_center: Vector2 = view.call("_body_position", focused_earth,
        float(view.call("_orbit_scale")))
    if moved_center.distance_to(view.size * 0.5) > 2.0:
        _fail("planet drifted from camera after a real orbit-angle change")
        return

    # Zooming back through the SAME detail threshold releases the lock.
    view.call("_zoom_at", view.size * 0.5, 1.0 / 32.0)
    if bool(view.call("is_body_focused")):
        _fail("zoom-out failed to release the followed planet")
        return
    for i in range(120):
        view.call("_process", 1.0 / 60.0)

    view.call("set_world", sol)

    # Progressive surface LOD must never pop in as an opaque overlay.
    # Same relative 2-notch transition for small moons and gas giants;
    # no special radius/zoom exception for Earth or Luna.
    var lod_samples: Array = [
        {"id": "lod-rock", "type": "planet", "biome": "terrestrial"},
        {"id": "lod-giant", "type": "planet", "biome": "gas_giant"},
        {"id": "lod-moon", "type": "moon", "biome": "lifeless"}
    ]
    for lod_body in lod_samples:
        var start_zoom: float = float(view.call(
            "_surface_detail_start_zoom", lod_body))
        view.set("_zoom", start_zoom)
        var first_radius: float = float(view.call("_body_size", lod_body))
        if absf(first_radius - 24.0) > 0.03:
            _fail("LOD threshold not aligned with current body size")
            return
        if absf(float(view.call("_surface_detail_alpha", lod_body))) > 0.01:
            _fail("surface detail appeared at full opacity at threshold")
            return
        view.set("_zoom", start_zoom * 1.32)
        var halfway: float = float(view.call(
            "_surface_detail_alpha", lod_body))
        if absf(halfway - 0.5) > 0.02:
            _fail("surface did not blend halfway after one wheel notch")
            return
        view.set("_zoom", start_zoom * 1.32 * 1.32)
        if absf(1.0 - float(view.call(
                "_surface_detail_alpha", lod_body))) > 0.02:
            _fail("surface did not reach original detail after two notches")
            return
        view.set("_zoom", start_zoom / 1.32)
        if float(view.call("_surface_detail_alpha", lod_body)) > 0.01:
            _fail("surface stays detailed below first appearance")
            return
    view.call("set_world", sol)

    # Soft orbit guides stay dim in the system view and fade as we approach
    # the planet, without hiding or altering any physical/world orbits.
    view.set("_zoom", 1.0)
    var distant_planet_alpha: float = float(view.call("_orbit_line_alpha", false))
    var distant_moon_alpha: float = float(view.call("_orbit_line_alpha", true))
    if distant_planet_alpha > 0.35 or distant_moon_alpha > distant_planet_alpha:
        _fail("distant system orbits are too bright")
        return
    view.set("_zoom", 32.0)
    var near_planet_alpha: float = float(view.call("_orbit_line_alpha", false))
    var near_moon_alpha: float = float(view.call("_orbit_line_alpha", true))
    if near_planet_alpha <= 0.0 or (
            near_planet_alpha >= distant_planet_alpha) or (
            near_moon_alpha >= distant_moon_alpha):
        _fail("near-surface orbit guides did not fade")
        return
    view.call("set_world", sol)

    # Approved Sol Lab baseline: 0.65 radial display compression.
    var earth: Dictionary = {}
    var luna: Dictionary = {}
    var mars: Dictionary = {}
    var jupiter: Dictionary = {}
    var mercury: Dictionary = {}
    var callisto: Dictionary = {}
    for body in sol.get("bodies", []):
        match str(body.get("id", "")):
            "earth":
                earth = body
            "luna":
                luna = body
            "mars":
                mars = body
            "jupiter":
                jupiter = body
            "mercury":
                mercury = body
            "callisto":
                callisto = body
    if earth.is_empty() or luna.is_empty() or mars.is_empty() or (
            jupiter.is_empty() or mercury.is_empty() or callisto.is_empty()):
        _fail("missing original Sol bodies")
        return
    var earth_r: float = float(earth["orbit_radius"])
    if absf(float(view.call("_radius_transform", earth_r)) -
            pow(earth_r, 0.65)) > 0.00001:
        _fail("Sol Lab compression baseline was lost")
        return

    # Readable symbols are not physical sizes, but maintain the hierarchy.
    var star_size: float = 13.5
    var jupiter_size: float = float(view.call("_body_size_at_zoom", jupiter, 1.0))
    var earth_size: float = float(view.call("_body_size_at_zoom", earth, 1.0))
    var mars_size: float = float(view.call("_body_size_at_zoom", mars, 1.0))
    var moon_size: float = float(view.call("_body_size_at_zoom", luna, 1.0))
    if not (star_size > jupiter_size and jupiter_size > earth_size and (
            earth_size > mars_size) and mars_size > moon_size):
        _fail("Sun / Jupiter / Earth / Mars / Moon symbols not ordered")
        return
    view.set("_zoom", 1.0)
    view.set("_pan", Vector2.ZERO)
    view.set("_draw_body_positions", {})
    var scale: float = float(view.call("_orbit_scale"))
    var mercury_pos: Vector2 = view.call("_body_position", mercury, scale)
    if mercury_pos.distance_to(view.size * 0.5) < 13.5 + (
            float(view.call("_body_size", mercury)) + 2.0):
        _fail("Sun covers Mercury on system overview")
        return

    # Real LOCAL Moon distance is 384,400 km, not 2.1-2.0 from
    # its legacy heliocentric seed orbit radius. Generic metadata path
    # never needs hardcoded satellite identities.
    var moon_local: float = float(view.call("_satellite_orbit_native_radius", luna))
    if absf(moon_local - 384400.0 / 149597870.7 * 2.0) > 0.0000001:
        _fail("Moon orbital separation does not use local km data")
        return
    if float(view.call("_satellite_orbit_native_radius", callisto)) <= moon_local:
        _fail("Callisto local orbit was not resolved")
        return
    var generic: Dictionary = {
        "id": "test-planetocentric-moon",
        "type": "moon",
        "parent_body_id": "earth",
        "satellite_orbit_radius_native": 0.02,
        "orbit_radius": earth_r,
        "current_angle": 37.0
    }
    var missing: Dictionary = generic.duplicate(true)
    missing.erase("satellite_orbit_radius_native")
    var missing_parent: Dictionary = view.call("_known_moon_parent", missing)
    if not missing_parent.is_empty():
        _fail("invented a satellite orbit without local radius")
        return
    var parent: Dictionary = view.call("_known_moon_parent", luna)
    if str(parent.get("id", "")) != "earth":
        _fail("Sol Moon does not orbit Earth visually")
        return
    var generic_parent: Dictionary = view.call("_known_moon_parent", generic)
    if str(generic_parent.get("id", "")) != "earth":
        _fail("generic explicit satellite parent was lost")
        return
    if float(view.call("_satellite_visibility", luna, earth, scale)) > 0.001:
        _fail("Moon must be hidden when it overlaps Earth on overview")
        return

    for zoom_value in [0.45, 1.0, 8.0, 32.0, 64.0, 128.0, 512.0]:
        var zoom: float = float(zoom_value)
        view.set("_zoom", zoom)
        view.set("_pan", Vector2.ZERO)
        view.set("_draw_body_positions", {})
        scale = float(view.call("_orbit_scale"))
        var earth_pos: Vector2 = view.call("_body_position", earth, scale)
        for child in [luna, generic]:
            var child_pos: Vector2 = view.call("_body_position", child, scale)
            var actual: float = child_pos.distance_to(earth_pos)
            var expected: float = float(view.call(
                "_satellite_orbit_radius", child, earth, scale))
            if absf(actual - expected) > maxf(0.05, expected * 0.0001):
                _fail("satellite projection mismatch at zoom " + str(zoom))
                return
            var combined: float = float(view.call("_body_size", earth)) + (
                float(view.call("_body_size", child)))
            var opacity: float = float(view.call(
                "_satellite_visibility", child, earth, scale))
            if opacity > 0.01 and actual < combined - 3.0:
                _fail("drawn satellite overlaps parent")
                return
            if zoom == 32.0 and opacity < 0.5:
                _fail("satellite did not emerge at local zoom")
                return
        if zoom == 32.0:
            var moon_pos: Vector2 = view.call("_body_position", luna, scale)
            var mars_pos: Vector2 = view.call("_body_position", mars, scale)
            if moon_pos.distance_to(earth_pos) >= (
                    mars_pos.distance_to(earth_pos)):
                _fail("Moon is projected farther away than Mars")
                return

    if JSON.stringify(sol) != before:
        _fail("satellite camera projection mutated frozen world")
        return
    print("P2 SEAMLESS ZOOM PASS: Sol Lab compression, Moon local orbit, camera and LOD; no world mutation")
    view.queue_free()
    quit(0)


func _fail(why: String) -> void:
    push_error("P2 SEAMLESS ZOOM FAIL: " + why)
    quit(1)
