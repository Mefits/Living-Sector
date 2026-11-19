extends SceneTree
## E: adapter regression. Fake runner tests checkpoint policy only;
## real paid economy remains covered by live_instrumentation_ab.
const Live = preload("res://tests/p2_perf_e_live_instrumentation_ab.gd")

class FakeRunner:
    extends RefCounted
    var tick_count: int = 0
    var checkpoint_calls: int = 0
    var refuse: bool = false
    var fail: bool = false
    var queued: bool = false

    func queue_control(command: String, amount: int = 1) -> bool:
        if refuse or command != "step" or amount != 1:
            return false
        queued = true
        return true

    func advance_frame(_delta: float) -> void:
        if queued and not fail:
            tick_count += 1
        queued = false

    func last_phase_failure() -> Dictionary:
        return {"reason": "failure"} if fail else {}

    func checkpoint() -> Dictionary:
        checkpoint_calls += 1
        return {"tick": tick_count, "world": {"cargo": tick_count},
            "ledger": {"receipts": []}, "rng": [tick_count], "bt": {}}

func _initialize() -> void:
    var adapter = Live.new()
    adapter._start_ms = Time.get_ticks_msec()
    adapter._active_stride = 10
    var plain := FakeRunner.new()
    var profiled := FakeRunner.new()
    for tick in range(1, 201):
        var p: Dictionary = adapter._step(plain, tick, false, false)
        var q: Dictionary = adapter._step(profiled, tick, true, false)
        if not p.get("ok", false) or not q.get("ok", false) or (
                p.has("checkpoint") or q.has("checkpoint") or
                p.has("checkpoint_usec") or q.has("checkpoint_usec")):
            _fail("warmup created checkpoint or failed at " + str(tick))
            return
    if plain.checkpoint_calls != 0 or profiled.checkpoint_calls != 0 or (
            adapter._warmup_plain != 200 or adapter._warmup_profiled != 200 or
            adapter._steps_plain != 200 or adapter._steps_profiled != 200):
        _fail("warmup counters / checkpoint policy")
        return
    if plain.checkpoint() != profiled.checkpoint() or (
            plain.checkpoint_calls != 1 or profiled.checkpoint_calls != 1):
        _fail("explicit warmup boundary parity")
        return
    for tick in range(201, 211):
        var p: Dictionary = adapter._step(plain, tick, false, true)
        var q: Dictionary = adapter._step(profiled, tick, true, true)
        var gate: bool = tick == 210
        if not p.get("ok", false) or not q.get("ok", false) or (
                p.has("checkpoint") != gate or q.has("checkpoint") != gate or
                p.has("checkpoint_usec") != gate or q.has("checkpoint_usec") != gate):
            _fail("measured gate policy at " + str(tick))
            return
    if plain.checkpoint_calls != 2 or profiled.checkpoint_calls != 2 or (
            adapter._warmup_plain != 200 or adapter._warmup_profiled != 200):
        _fail("measured checkpoint accounting / warmup isolation")
        return
    # Negative: stale SourceClock, refused control, failed paid tick must
    # not be accepted or silently fabricate a checkpoint.
    var stale := FakeRunner.new()
    if adapter._step(stale, 2, false, true).get("ok", false):
        _fail("stale source clock accepted")
        return
    stale.refuse = true
    if adapter._step(stale, 1, false, true).get("ok", false):
        _fail("refused paid step accepted")
        return
    stale.refuse = false
    stale.fail = true
    if adapter._step(stale, 1, false, true).get("ok", false) or stale.checkpoint_calls != 0:
        _fail("failed paid tick accepted")
        return
    print("P2_PERF_E_LIVE_AB_WARMUP_ISOLATION_PASS")
    quit(0)

func _fail(message: String) -> void:
    push_error("P2_PERF_E_LIVE_AB_WARMUP_ISOLATION_FAIL " + message)
    quit(1)
