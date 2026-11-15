extends SceneTree
## GUI read-only projection: one detached N38 frame can feed observer,
## fleet and summary with identical values and without touching live N39.
const NativeData = preload("res://scripts/native_data.gd")
const Runner = preload("res://scripts/sim/phase2/n158_production_runtime.gd")

func _initialize() -> void:
    var sim = Runner.new()
    if not sim.start_from_seed(NativeData.load_current_world()):
        _fail("native runtime seed rejected")
        return
    if not sim.queue_control("pause") or not sim.queue_control("speed", 8.0):
        _fail("source clock controls rejected")
        return
    sim.advance_frame(0.0)
    if not sim.queue_control("step", 1):
        _fail("native step rejected")
        return
    sim.advance_frame(0.0)
    if not sim.last_phase_failure().is_empty():
        _fail("source tick rejected")
        return
    var before: Dictionary = sim.checkpoint()
    var detached: Dictionary = before["native_production"]["world"]
    if sim.economy_summary() != sim.economy_summary(detached):
        _fail("observer summary differs from canonical World projection")
        return
    if sim.fleet_snapshot() != detached["ships"]:
        _fail("observer fleet differs from native N39 fleet")
        return
    if sim.economy_snapshot() != detached:
        _fail("observer economy differs from native N39 World")
        return
    var pristine: Dictionary = sim.checkpoint()
    # The summary may only read the supplied detached projection.
    var ignored: Dictionary = sim.economy_summary(detached)
    if ignored.is_empty() or sim.checkpoint() != pristine:
        _fail("summary projection mutated live authority")
        return
    detached["ships"].clear()
    detached["markets"].clear()
    if sim.checkpoint() != pristine:
        _fail("observer checkpoint alias reached live authority")
        return
    print("P2_OBSERVER_CHECKPOINT_PROJECTION_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_OBSERVER_CHECKPOINT_PROJECTION_FAIL: " + reason)
    quit(1)
