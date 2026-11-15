extends SceneTree
## Execute only when Godot 4 is available:
## godot --headless --path godot --script res://scripts/sim/phase1/n39_headless_entry.gd
const Checks = preload("res://scripts/sim/phase1/n39_source_regression_checks.gd")

func _initialize() -> void:
    var result: Dictionary = Checks.run_all()
    print("N39 source probes: ", result.get("passed", 0), "/",
        result.get("total", 0), " passed")
    for name in result.get("checks", {}):
        if not bool(result["checks"][name]):
            push_error("N39 regression failed: " + str(name))
    quit(0 if result.get("all_passed", false) else 1)
