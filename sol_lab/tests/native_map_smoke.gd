extends SceneTree
const View = preload("res://scripts/star_system_view.gd")
const Profile = preload("res://scripts/sol_profile.gd")

func _initialize() -> void:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(
        "res://data/sol.json"))
    if not (parsed is Dictionary):
        push_error("NATIVE_VIEW_FAIL: Sol seed")
        quit(1)
        return
    var world: Dictionary = parsed
    if not Profile.apply_world(world):
        push_error("NATIVE_VIEW_FAIL: moon profile")
        quit(1)
        return
    var only: Array = []
    for b in world.get("bodies", []):
        if str(b.get("id", "")) in ["earth", "luna", "mars"]:
            only.append(b.duplicate(true))
    var view_world: Dictionary = world.duplicate(true)
    view_world["bodies"] = only
    var view = View.new()
    get_root().add_child(view)
    view.set_world(view_world)
    view.select_body("earth")
    view.update_world(view_world)
    var okay: bool = view_world["bodies"].size() == 3 and (
        str(world["system"]["id"]) == "system-sol")
    view.queue_free()
    if okay:
        print("SOL_NATIVE_VIEW_SMOKE_PASS")
        quit(0)
    else:
        push_error("NATIVE_VIEW_SMOKE_FAIL")
        quit(1)
