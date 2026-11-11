extends SceneTree
## Small headless Godot acceptance when the binary is available:
## godot --headless --path godot --script res://tests/p0_seed_check.gd
## No economic ticks, expensive CI or Rust dependencies.

const NativeData = preload("res://scripts/native_data.gd")
const WorldModel = preload("res://scripts/sim/world_model.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        push_error("P0_SEED_FAIL " + str(seed["error"]))
        quit(1)
        return
    var stats: Dictionary = seed.get("seed_stats", {})
    var expected: Dictionary = {
        "systems": 8, "factions": 3, "bodies": 47,
        "facilities": 15, "ships": 24, "markets": 3,
        "populations": 3
    }
    for key in expected.keys():
        if stats.get(key, -1) != expected[key]:
            push_error("P0_SEED_FAIL %s got %s expected %s" % [
                key, stats.get(key, null), expected[key]
            ])
            quit(1)
            return
    var model = WorldModel.new()
    if not model.load_seed(seed):
        push_error("P0_SEED_FAIL world model indexing")
        quit(1)
        return
    var sol: Dictionary = model.system_by_id("system-sol")
    if sol.get("bodies", []).size() != 13:
        push_error("P0_SEED_FAIL Sol bodies should be 13")
        quit(1)
        return
    var original_size: int = sol["bodies"].size()
    sol["bodies"].clear()  # copy must not modify actual indexed model
    if model.system_by_id("system-sol").get("bodies", []).size() != original_size:
        push_error("P0_SEED_FAIL the inspector modified seed state")
        quit(1)
        return
    if model.seed_universe_position("system-alpha-centauri") != Vector2(40, 10):
        push_error("P0_SEED_FAIL source universe offset")
        quit(1)
        return
    print("P0_SEED_PASS ", JSON.stringify(stats))
    quit(0)
