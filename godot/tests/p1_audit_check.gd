extends SceneTree
## Short headless audit for P1 input boundaries and command parity.
## Run: Godot --headless --path godot --script res://tests/p1_audit_check.gd

const NativeData = preload("res://scripts/native_data.gd")
const WorldModel = preload("res://scripts/sim/world_model.gd")
const Runner = preload("res://scripts/sim/tick_runner.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("seed missing: " + str(seed["error"]))
        return

    var original_json: String = JSON.stringify(seed)
    var world = WorldModel.new()
    if not world.load_seed(seed):
        _fail("validated Galaxy seed rejected")
        return
    world.advance_orbits(0.03125)
    if JSON.stringify(seed) != original_json:
        _fail("world model mutated importer-owned seed")
        return

    var wrong_containers: Dictionary = {"worlds": "not-an-array", "factions": []}
    if WorldModel.new().load_seed(wrong_containers):
        _fail("non-array worlds accepted")
        return

    var invalid_angle: Dictionary = seed.duplicate(true)
    invalid_angle["worlds"][0]["bodies"][0]["current_angle"] = 360
    if WorldModel.new().load_seed(invalid_angle):
        _fail("out-of-range orbital angle accepted")
        return

    var duplicate_body: Dictionary = seed.duplicate(true)
    duplicate_body["worlds"][0]["bodies"][1]["id"] = duplicate_body["worlds"][0]["bodies"][0]["id"]
    if WorldModel.new().load_seed(duplicate_body):
        _fail("duplicate body ID accepted")
        return

    var runner = Runner.new()
    if not runner.start_from_seed(seed):
        _fail("runner seed boot")
        return
    if runner.queue_control("pause", "unexpected") or runner.queue_control("resume", 0):
        _fail("malformed pause/resume control accepted")
        return
    if not runner.queue_control("pause"):
        _fail("valid pause command rejected")
        return
    runner.advance_frame(0.0)
    var malformed_checkpoint: Dictionary = runner.checkpoint()
    malformed_checkpoint["pending_controls"] = [{"kind": "pause", "value": "unexpected"}]
    if runner.restore_checkpoint(malformed_checkpoint, seed):
        _fail("malformed persisted control accepted")
        return
    if not runner.clock.paused:
        _fail("failed restore changed the live clock")
        return

    print("P1_AUDIT_PASS: seed boundaries, copy isolation, orbit range and command parity")
    quit(0)

func _fail(problem: String) -> void:
    push_error("P1_AUDIT_FAIL: " + problem)
    quit(1)
