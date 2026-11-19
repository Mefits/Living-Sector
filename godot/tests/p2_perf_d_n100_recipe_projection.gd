extends SceneTree
## Run headless: godot --headless --path godot --script res://tests/p2_perf_d_n100_recipe_projection.gd
const Planning = preload("res://scripts/sim/phase2/unified_native_hybrid_planning.gd")
const Recipes = preload("res://scripts/sim/economy/native_recipes.gd")

func _initialize() -> void:
    var first: Array = Planning._recipe_projection()
    var expected: Array = []
    for original in Recipes.TABLE:
        var ins: Array = []
        var outs: Array = []
        var input_names: Array = original["in"].keys()
        var output_names: Array = original["out"].keys()
        input_names.sort()
        output_names.sort()
        for good in input_names:
            ins.append([str(good), int(original["in"][good])])
        for good in output_names:
            outs.append([str(good), int(original["out"][good])])
        expected.append({"recipe_id": str(original["id"]),
            "facility_type": str(original["facility"]),
            "inputs": ins, "outputs": outs})
    if first != expected:
        push_error("N100 cached recipe projection differs from source ordering")
        quit(1)
        return
    var second: Array = Planning._recipe_projection()
    if first.is_empty():
        push_error("N100 source catalogue unexpectedly empty")
        quit(1)
        return
    first[0]["inputs"].clear()
    first[0]["recipe_id"] = "corrupted"
    first.clear()
    if second != expected or Planning._recipe_projection() != expected:
        push_error("N100 cached recipe projection leaked a mutable alias")
        quit(1)
        return
    print("PASS p2_perf_d_n100_recipe_projection")
    quit(0)
