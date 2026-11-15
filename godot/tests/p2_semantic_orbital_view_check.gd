extends SceneTree
## One acceptance fixture for the THREE UI levels and honest moon display.
## No generated planets, parent IDs, market or tick changes.
## godot --headless --path godot --script res://tests/p2_semantic_orbital_view_check.gd
const Native = preload("res://scripts/native_data.gd")
const StarView = preload("res://scripts/star_system_view.gd")

func _initialize() -> void:
    var seed: Dictionary = Native.load_current_world()
    if seed.has("error"):
        _fail("frozen Galaxy not loaded: " + str(seed["error"]))
        return
    var sol: Dictionary = {}
    var nadir: Dictionary = {}
    for item in seed.get("worlds", []):
        var id: String = str(item.get("system", {}).get("id", ""))
        if id == "system-sol":
            sol = item.duplicate(true)
        elif id == "system-nadir":
            nadir = item.duplicate(true)
    if sol.is_empty() or nadir.is_empty():
        _fail("source solar/nadir worlds missing")
        return
    var ui = StarView.new()
    ui.size = Vector2(1040.0, 680.0)
    ui.set_world(sol)
    var earth: Dictionary = ui._body_by_id("earth")
    var luna: Dictionary = ui._body_by_id("luna")
    var jupiter: Dictionary = ui._body_by_id("jupiter")
    var callisto: Dictionary = ui._body_by_id("callisto")
    if ui._known_moon_parent(luna).get("id", "") != "earth":
        _fail("Luna still circles the Sun rather than actual Earth parent")
        return
    if ui._known_moon_parent(callisto).get("id", "") != "jupiter":
        _fail("Callisto still circles the Sun rather than real Jupiter parent")
        return
    var scale: float = ui._orbit_scale()
    var center: Vector2 = ui._body_position(earth, scale)
    var moon_pos: Vector2 = ui._body_position(luna, scale)
    var ring: float = ui._moon_visual_orbit(luna, earth)
    if absf(center.distance_to(moon_pos) - ring) > 0.1:
        _fail("Luna has not been placed on the parent-centered orbital ring")
        return
    var previous_angle: float = float(luna["current_angle"])
    var advanced: Dictionary = sol.duplicate(true)
    for body in advanced["bodies"]:
        if str(body.get("id", "")) == "luna":
            body["current_angle"] = fposmod(previous_angle + 70.0, 360.0)
    ui.update_world(advanced)
    var moved: Vector2 = ui._body_position(ui._body_by_id("luna"), scale)
    if moon_pos.distance_to(moved) < 0.5 or absf(center.distance_to(moved) - ring) > 0.1:
        _fail("live Lunar angle did not orbit actual moving parent")
        return
    if not ui.focus_body("earth") or not ui.is_body_focused():
        _fail("system body double-click cannot enter globe detail mode")
        return
    ui.update_world(sol)
    if not ui.is_body_focused():
        _fail("ongoing native orbit tick unexpectedly cancelled globe focus")
        return
    ui.reset_view()
    if not ui.is_body_focused():
        _fail("center camera should not close the globe")
        return
    ui.unfocus_body()
    if ui.is_body_focused():
        _fail("back to orbital system level failed")
        return
    ui.set_world(nadir)
    var wreck: Dictionary = ui._body_by_id("nadir-wreckhold")
    if wreck.is_empty() or not ui._known_moon_parent(wreck).is_empty():
        _fail("fictional Wreckhold acquired an invented parent")
        return
    print("P2_SEMANTIC_SYSTEM_GLOBE_AND_KNOWN_MOON_ORBITS_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_SEMANTIC_ORBIT_FAIL: " + reason)
    quit(1)
