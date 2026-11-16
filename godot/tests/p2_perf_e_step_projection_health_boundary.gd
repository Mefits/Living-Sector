extends SceneTree
## PERF E: a failed N158 tick must not leak a plausible UI frame.
const Binding = preload("res://scripts/sim/phase2/n158_owner_step_binding.gd")

class FakeClock:
    extends RefCounted
    var paused: bool = true
    var world_speed: float = 1.0

class FakeRunner:
    extends RefCounted
    var clock: RefCounted = FakeClock.new()
    var tick_count: int = 7
    var started: bool = true
    var failure: String = ""
    var reject_step: bool = false
    var fail_during_advance: bool = false
    func is_started() -> bool:
        return started
    func last_phase_failure() -> String:
        return failure
    func queue_control(command: String, amount: int) -> bool:
        return command == "step" and amount == 1 and not reject_step
    func advance_frame(_delta: float) -> void:
        if fail_during_advance:
            failure = "phase_failure"
        else:
            tick_count += 1

func _initialize() -> void:
    var runner := FakeRunner.new()
    var binding = Binding.new()
    assert(binding.bind_authoritative(runner))
    assert(binding.projection_executor(7).get("tick", -1) == 7)
    assert(binding.projection_executor(6).is_empty())
    runner.fail_during_advance = true
    var result: Dictionary = binding.tick_executor()
    assert(not result.get("success", false))
    assert(binding.projection_executor(7).is_empty())
    runner.failure = ""
    runner.started = false
    assert(binding.projection_executor(7).is_empty())
    runner.started = true
    runner.clock = null
    assert(binding.projection_executor(7).is_empty())
    var missing_clock := FakeRunner.new()
    missing_clock.clock = null
    assert(not Binding.new().bind_authoritative(missing_clock))
    print("P2_PERF_E_STEP_PROJECTION_HEALTH_PASS")
    quit()
