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

    # Root-cause regression: all relative-orbit separation must obey the
    # SAME camera scale as full-system orbital distance. A moon must not
    # grow into its parent when zoom grows past the old sqrt(zoom) clamp.
    var earth: Dictionary = {}
    var luna: Dictionary = {}
    for body in sol.get("bodies", []):
        if str(body.get("id", "")) == "earth":
            earth = body
        elif str(body.get("id", "")) == "luna":
            luna = body
    if earth.is_empty() or luna.is_empty():
        _fail("original Earth/Luna seed missing")
        return
    # Also check an arbitrary child via parent_body_id; no Luna ID-specific
    # drawing exceptions are allowed.
    var generic_child: Dictionary = {
        "id": "ui-test-satellite",
        "type": "moon",
        "parent_body_id": "earth",
        "orbit_radius": earth.get("orbit_radius", 0.0),
        "current_angle": 37.0,
        "biome": "lifeless"
    }
    var known_parent: Dictionary = view.call("_known_moon_parent", luna)
    var generic_parent: Dictionary = view.call("_known_moon_parent", generic_child)
    if str(known_parent.get("id", "")) != "earth" or (
            str(generic_parent.get("id", "")) != "earth"):
        _fail("parent relationships were not resolved")
        return

    var base_luna_separation: float = -1.0
    var base_generic_separation: float = -1.0
    for zoom_value in [0.45, 1.0, 8.0, 32.0, 64.0, 128.0, 512.0]:
        var z: float = float(zoom_value)
        view.set("_zoom", z)
        view.set("_pan", Vector2.ZERO)
        view.set("_draw_body_positions", {})
        var orbit_scale: float = float(view.call("_orbit_scale"))
        var earth_point: Vector2 = view.call("_body_position", earth, orbit_scale)
        for child in [luna, generic_child]:
            var screen_point: Vector2 = view.call("_body_position", child, orbit_scale)
            var separation: float = screen_point.distance_to(earth_point)
            var expected: float = float(view.call("_satellite_orbit_radius", child, earth))
            # Vector2 is float32; large positions at ×512 need a relative epsilon.
            if absf(separation - expected) > maxf(0.05, expected * 0.00005):
                _fail("child/parent projection mismatch at zoom " + str(z))
                return
            var footprint: float = float(view.call("_body_size", earth)) + (
                float(view.call("_body_size", child)))
            if separation <= footprint:
                _fail("satellite overlaps parent at zoom " + str(z))
                return
            var unzoomed: float = separation / z
            if str(child.get("id", "")) == "luna":
                if base_luna_separation < 0.0:
                    base_luna_separation = unzoomed
                elif absf(unzoomed - base_luna_separation) > 0.02:
                    _fail("Luna relative orbit did not scale linearly")
                    return
            else:
                if base_generic_separation < 0.0:
                    base_generic_separation = unzoomed
                elif absf(unzoomed - base_generic_separation) > 0.02:
                    _fail("generic satellite orbit did not scale linearly")
                    return

    if JSON.stringify(sol) != before:
        _fail("satellite camera projection mutated frozen world")
        return
    print("P2 SEAMLESS ZOOM PASS: orbit/globe camera + generic satellite projection; no world mutation")
    view.queue_free()
    quit(0)


func _fail(why: String) -> void:
    push_error("P2 SEAMLESS ZOOM FAIL: " + why)
    quit(1)
