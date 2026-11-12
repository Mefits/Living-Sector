extends SceneTree
## godot --headless --path godot --script res://tests/n24_diagnostic_check.gd
const NativeData = preload("res://scripts/native_data.gd")
const Runner = preload("res://scripts/sim/tick_runner.gd")
const Diagnostic = preload("res://scripts/sim/diagnostic_snapshot.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("seed load")
        return
    var runner = Runner.new()
    if not runner.start_from_seed(seed):
        _fail("runner boot")
        return
    var before: Dictionary = runner.checkpoint()
    var first: Dictionary = Diagnostic.capture(runner)
    var second: Dictionary = Diagnostic.capture(runner)
    if JSON.stringify(first) != JSON.stringify(second):
        _fail("nondeterministic diagnostics")
        return
    if JSON.stringify(before) != JSON.stringify(runner.checkpoint()):
        _fail("diagnostics mutated authoritative state")
        return
    if first.get("systems", []).size() != 8 or first.get("faction_count", -1) != 3:
        _fail("wrong frozen seed count")
        return
    if first.get("bodies", []).size() != 47 or not first.get("warnings", []).is_empty():
        _fail("missing bodies or invalid orbit")
        return
    if first.get("economic_state_available", true):
        _fail("P1 must not claim economic runtime state")
        return
    runner.queue_control("pause")
    runner.advance_frame(0.0)
    runner.queue_control("step", 3)
    runner.advance_frame(0.0)
    var advanced: Dictionary = Diagnostic.capture(runner)
    if advanced.get("tick", -1) != 3 or advanced.get("orbital_angles", []) == first.get("orbital_angles", []):
        _fail("tick/orbits not reflected")
        return
    var saved: Dictionary = runner.checkpoint()
    var resumed = Runner.new()
    if not resumed.start_from_seed(seed) or not resumed.restore_checkpoint(saved, seed):
        _fail("restore failed")
        return
    if JSON.stringify(advanced) != JSON.stringify(Diagnostic.capture(resumed)):
        _fail("snapshot changed across save/load")
        return
    print("N24_DIAGNOSTICS_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("N24_DIAGNOSTICS_FAIL: " + reason)
    quit(1)
