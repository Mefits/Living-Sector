extends SceneTree
const SCHEDULER = preload("res://scripts/sim/phase2/n158_worker_tick_scheduler.gd")

func _initialize() -> void:
    var s = SCHEDULER.new()
    if not s.configure(0.25) or s.configure(0.0):
        _fail("tick interval validation")
        return
    if not s.add_elapsed(1.0) or s.begin_tick():
        _fail("paused scheduler advanced without step")
        return
    if not s.apply_control("step") or not s.begin_tick() or s.begin_tick():
        _fail("single owner step admission")
        return
    if not s.finish_tick(true) or s.begin_tick():
        _fail("paused step repeated")
        return
    if not s.apply_control("speed", {"value": 8.0}) or not s.apply_control("resume"):
        _fail("control commands rejected")
        return
    if not s.add_elapsed(0.125):
        _fail("elapsed rejected")
        return
    for i in range(4):
        if not s.begin_tick() or not s.finish_tick(true):
            _fail("four logical ticks not admitted")
            return
    if s.begin_tick() or int(s.snapshot()["completed"]) != 5:
        _fail("credit overspent or completed count wrong")
        return
    if not s.apply_control("pause") or not s.add_elapsed(0.5) or s.begin_tick():
        _fail("pause continued consuming wall time")
        return
    if s.apply_control("speed", {"value": -1.0}) or s.apply_control("speed", {"value": "fast"}):
        _fail("invalid speed accepted")
        return
    if s.add_elapsed(-0.1) or s.add_elapsed(INF):
        _fail("invalid elapsed accepted")
        return
    if not s.apply_control("step") or not s.begin_tick():
        _fail("second step rejected")
        return
    if s.apply_control("pause") or s.reset_after_load():
        _fail("mutation allowed during inflight transaction")
        return
    if not s.finish_tick(true) or not s.reset_after_load():
        _fail("load boundary reset rejected")
        return
    if s.snapshot()["credit"] != 0.0 or s.snapshot()["steps"] != 0:
        _fail("load boundary leaked pending ticks")
        return
    if not s.apply_control("step") or not s.begin_tick() or s.finish_tick(false):
        _fail("failure transaction not frozen")
        return
    if not s.snapshot()["frozen"] or s.begin_tick() or s.apply_control("resume"):
        _fail("failure freeze violated")
        return
    print("P2_PERF_E_WORKER_TICK_SCHEDULER_PASS pause=true fifo_boundary=true no_skip=true load=true freeze=true")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_WORKER_TICK_SCHEDULER_FAIL: " + reason)
    quit(1)
