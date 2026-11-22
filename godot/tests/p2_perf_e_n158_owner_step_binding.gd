extends SceneTree
const BINDING = preload("res://scripts/sim/phase2/n158_owner_step_binding.gd")
const ADAPTER = preload("res://scripts/sim/phase2/n158_worker_execution_adapter.gd")

class FakeClock:
    extends RefCounted
    var paused: bool = true
    var world_speed: float = 1.0

class FakeRunner:
    extends RefCounted
    var clock = FakeClock.new()
    var tick_count: int = 0
    var started: bool = true
    var failure: String = ""
    var reject_step: bool = false
    var double_step: bool = false
    var queued: bool = false
    var calls: int = 0

    func is_started() -> bool:
        return started

    func last_phase_failure() -> String:
        return failure

    func queue_control(kind: String, count: int = 0) -> bool:
        if reject_step or kind != "step" or count != 1:
            return false
        queued = true
        return true

    func advance_frame(delta: float) -> void:
        assert(delta == 0.0)
        calls += 1
        if queued:
            tick_count += 2 if double_step else 1
            queued = false

func _initialize() -> void:
    var runner = FakeRunner.new()
    var binding = BINDING.new()
    assert(binding.bind_authoritative(runner))
    var adapter = ADAPTER.new()
    assert(adapter.owner_configure(1.0))
    assert(adapter.ui_enqueue("step") > 0)
    var result: Dictionary = adapter.owner_pump(0.0,
        Callable(binding, "tick_executor"), Callable(binding, "projection_executor"))
    assert(result.get("success") == true and result.get("tick") == 1)
    assert(runner.calls == 1 and runner.tick_count == 1)
    var frame: Dictionary = adapter.ui_read_frame()
    assert(frame["ready"] and frame["view"]["tick"] == 1)
    frame["view"]["tick"] = 999
    assert(adapter.ui_read_frame()["view"]["tick"] == 1)

    # Running mode must not inject a step or silently change N158 speed.
    runner.clock.paused = false
    var rejected: Dictionary = binding.tick_executor()
    assert(not rejected["success"] and runner.calls == 1)
    runner.clock.paused = true
    runner.reject_step = true
    rejected = binding.tick_executor()
    assert(not rejected["success"] and runner.calls == 1)
    runner.reject_step = false

    # A failed or double-advanced authoritative tick must never be published.
    runner.double_step = true
    assert(adapter.ui_enqueue("step") > 0)
    result = adapter.owner_pump(0.0,
        Callable(binding, "tick_executor"), Callable(binding, "projection_executor"))
    assert(not result["success"] and result["error"] == "authoritative_tick_failed")
    assert(adapter.ui_read_frame()["view"]["tick"] == 1)
    assert(adapter.ui_enqueue("step") == -1)

    # Projection must reject a tick other than the current committed tick.
    assert(binding.projection_executor(-1).is_empty())
    print("P2_PERF_E_N158_OWNER_STEP_BINDING_PASS")
    quit()
