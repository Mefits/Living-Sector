extends SceneTree
## N157 Phase1 source-only smoke runner. Not yet executed.
## godot --headless --path godot --script res://scripts/sim/phase1/n157_headless_entry.gd
const PersistenceChecks = preload("res://scripts/sim/phase1/n157_source_persistence_checks.gd")
const GridChecks = preload("res://scripts/sim/phase1/n157_source_grid_checks.gd")

func _initialize() -> void:
    var a: Dictionary = PersistenceChecks.run_all()
    var b: Dictionary = GridChecks.run_all()
    print("N157 persistence checks: ", a.get("passed", 0),
        "/", a.get("total", 0))
    print("N157 grid checks: ", b.get("passed", 0),
        "/", b.get("total", 0))
    for name in a.get("checks", {}):
        if not a["checks"][name]:
            push_error("N157 persistence: " + str(name))
    for name in b.get("checks", {}):
        if not b["checks"][name]:
            push_error("N157 spatial grid: " + str(name))
    quit(0 if a.get("all_passed", false) and
        b.get("all_passed", false) else 1)
