extends SceneTree
## Headless: godot --headless --path godot --script res://tests/n62_runtime_readiness_check.gd
const Readiness = preload("res://scripts/sim/runtime_readiness.gd")
const NativeData = preload("res://scripts/native_data.gd")
const Runner = preload("res://scripts/sim/tick_runner.gd")

func _initialize() -> void:
    var report: Dictionary = Readiness.run_preflight()
    if not report.get("ok", false):
        _fail("actual P1 bootstrap: " + JSON.stringify(report))
        return
    var seed: Dictionary = NativeData.load_current_world()
    var runner = Runner.new()
    if not runner.start_from_seed(seed):
        _fail("runner failed to boot")
        return
    var before: String = JSON.stringify(runner.checkpoint())
    var initial: Dictionary = Readiness.audit_runner(runner)
    if not initial["ok"] or JSON.stringify(runner.checkpoint()) != before:
        _fail("read-only audit mutated runner")
        return
    var broken: Dictionary = seed.duplicate(true)
    broken["seed_stats"]["ships"] = 25
    if Readiness.audit_seed(broken)["ok"]:
        _fail("incorrect ship count accepted")
        return
    broken = seed.duplicate(true)
    broken.erase("worlds")
    if Readiness.audit_seed(broken)["ok"]:
        _fail("missing worlds accepted")
        return
    if runner.queue_control("transfer_credits", 1):
        _fail("P1 accepted unported economy command")
        return
    runner.queue_control("pause")
    runner.queue_control("step", 2)
    runner.advance_frame(0.0)
    if runner.tick_count != 2 or not Readiness.audit_runner(runner)["ok"]:
        _fail("manual tick readiness failed")
        return
    var checkpoint: Dictionary = runner.checkpoint()
    var corrupted: Dictionary = checkpoint.duplicate(true)
    corrupted["seed_fingerprint"] = "wrong-world"
    if runner.restore_checkpoint(corrupted, seed) or runner.tick_count != 2:
        _fail("invalid checkpoint partially restored")
        return
    if JSON.stringify(runner.checkpoint()) != JSON.stringify(checkpoint):
        _fail("failed restore changed authoritative state")
        return
    print("N62_RUNTIME_READINESS_PASS P1 seed/scene/tick/read-only/corrupt-restore")
    quit(0)

func _fail(reason: String) -> void:
    push_error("N62_RUNTIME_READINESS_FAIL " + reason)
    quit(1)
