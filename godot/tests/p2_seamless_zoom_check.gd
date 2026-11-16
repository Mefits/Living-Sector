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

    print("P2 SEAMLESS ZOOM PASS: orbit to globe in same view; no world mutation")
    view.queue_free()
    quit(0)


func _fail(why: String) -> void:
    push_error("P2 SEAMLESS ZOOM FAIL: " + why)
    quit(1)
