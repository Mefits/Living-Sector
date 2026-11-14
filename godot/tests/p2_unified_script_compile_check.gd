extends SceneTree
## One actual GDScript parse/preload sweep for the entire unified port.
## Run: godot --headless --path godot --script res://tests/p2_unified_script_compile_check.gd
## Does NOT instantiate gameplay components or fabricate a live ECS.
var _paths: PackedStringArray = PackedStringArray()

func _initialize() -> void:
    if not _collect("res://scripts"):
        push_error("P2_UNIFIED_PARSE_FAIL: could not enumerate scripts")
        quit(1)
        return
    _paths.sort()
    var loaded: int = 0
    var failed: PackedStringArray = PackedStringArray()
    for path in _paths:
        var resource: Resource = ResourceLoader.load(
            path, "Script", ResourceLoader.CACHE_MODE_IGNORE)
        if resource == null or not (resource is Script) or not resource.can_instantiate():
            failed.append(path)
        else:
            loaded += 1
    print("P2_UNIFIED_PARSE_SCAN: loaded=", loaded, " total=", _paths.size(),
        " failures=", failed.size())
    for path in failed:
        push_error("P2_UNIFIED_GDSCRIPT_ERROR: " + path)
    quit(0 if failed.is_empty() and loaded > 0 else 1)

func _collect(dir_path: String) -> bool:
    var d: DirAccess = DirAccess.open(dir_path)
    if d == null:
        return false
    d.list_dir_begin()
    var filename: String = d.get_next()
    while not filename.is_empty():
        if filename != "." and filename != "..":
            var full: String = dir_path.path_join(filename)
            if d.current_is_dir():
                if not _collect(full):
                    d.list_dir_end()
                    return false
            elif filename.ends_with(".gd"):
                _paths.append(full)
        filename = d.get_next()
    d.list_dir_end()
    return true
