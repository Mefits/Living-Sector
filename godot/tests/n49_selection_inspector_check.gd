extends SceneTree
## N49: run with godot --headless --path godot --script res://tests/n49_selection_inspector_check.gd
const NativeData = preload("res://scripts/native_data.gd")
const WorldModel = preload("res://scripts/sim/world_model.gd")
const Inspector = preload("res://scripts/view/selection_inspector.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("seed load: " + str(seed["error"]))
        return
    var world = WorldModel.new()
    if not world.load_seed(seed):
        _fail("world load")
        return
    var inspector = Inspector.new()
    var before: String = JSON.stringify(world.worlds())
    var worlds: Array = world.worlds()
    if worlds.size() != 8:
        _fail("unexpected system count")
        return
    var ids: Array[String] = []
    for entry in worlds:
        ids.append(str(entry.get("system", {}).get("id", "")))
    ids.sort()
    for sid in ids:
        var a: Dictionary = inspector.inspect(world, sid, 0)
        var b: Dictionary = inspector.inspect(world, sid, 0)
        if not a.get("ok", false) or JSON.stringify(a) != JSON.stringify(b):
            _fail("invalid or nondeterministic " + sid + " " + str(a.get("errors", [])))
            return
        if a.get("units", "") != "native_universe_offset_not_light_years":
            _fail("unit provenance")
            return
    if inspector.inspect(world, "not-a-system", 0).get("ok", true):
        _fail("unknown system accepted")
        return
    if inspector.inspect(world, ids[0], -1).get("ok", true):
        _fail("negative tick accepted")
        return
    if JSON.stringify(world.worlds()) != before:
        _fail("read-only inspector mutated world")
        return
    var sid: String = ids[0]
    var first: Dictionary = inspector.inspect(world, sid, 0)
    world.advance_orbits(1.0)
    var second: Dictionary = inspector.inspect(world, sid, 1)
    if second.get("tick", -1) != 1 or first.get("tick", -1) != 0:
        _fail("tick mismatch")
        return
    print("N49 PASS: 8 native systems, deterministic selection, no mutation, fail-closed")
    quit(0)

func _fail(message: String) -> void:
    push_error("N49 FAIL: " + message)
    quit(1)
