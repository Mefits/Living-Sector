extends SceneTree
## Boundary regression only: deliberately no N158 thread or simulation.
const BRIDGE = preload("res://scripts/sim/phase2/n158_worker_owner_bridge.gd")

func _initialize() -> void:
    var b = BRIDGE.new()
    if not b.owner_publish_committed(10, {"ships": [{"id": 1}]}):
        _fail("initial committed frame rejected")
        return
    var frame: Dictionary = b.ui_read_frame()
    frame["view"]["ships"][0]["id"] = 99
    if b.ui_read_frame()["view"]["ships"][0]["id"] != 1:
        _fail("mutable UI alias escaped")
        return
    if b.owner_publish_committed(9, {}) or b.owner_publish_committed(11, {"object": RefCounted.new()}):
        _fail("stale or live-object frame accepted")
        return
    var load_id: int = b.ui_enqueue("load", {"slot": "autosave"})
    var step_id: int = b.ui_enqueue("step")
    var load: Dictionary = b.owner_take_command()
    if int(load.get("id", -1)) != load_id or not b.owner_take_command().is_empty():
        _fail("concurrent owner command accepted")
        return
    if b.owner_publish_committed(11, {}) or b.owner_finish_command(step_id, true):
        _fail("frame or wrong acknowledgement accepted during load")
        return
    if not b.owner_finish_command(load_id, false, "disk error"):
        _fail("failed load could not be acknowledged")
        return
    if b.ui_read_frame()["tick"] != 10 or b.ui_read_frame()["epoch"] != 0:
        _fail("failed load incorrectly reset committed frame")
        return
    var step: Dictionary = b.owner_take_command()
    if int(step.get("id", -1)) != step_id or not b.owner_finish_command(step_id, true):
        _fail("FIFO step not completed")
        return
    var retry_id: int = b.ui_enqueue("load", {"slot": "autosave"})
    if int(b.owner_take_command().get("id", -1)) != retry_id or not b.owner_finish_command(retry_id, true):
        _fail("successful load not completed")
        return
    if b.ui_read_frame()["ready"] or b.ui_read_frame()["epoch"] != 1:
        _fail("successful load did not invalidate old epoch")
        return
    if not b.owner_publish_committed(2, {"tick": 2}) or b.owner_publish_committed(2, {}):
        _fail("restored tick publication or monotonic guard broken")
        return
    b.owner_freeze("simulation transaction failed")
    if b.ui_enqueue("pause") != -1 or b.owner_publish_committed(3, {}) or not b.owner_take_command().is_empty():
        _fail("failure freeze did not stop commands/frames")
        return
    if not b.ui_status()["failed"] or b.ui_read_frame()["tick"] != 2:
        _fail("failure diagnostics or last good frame lost")
        return
    print("P2_PERF_E_OWNER_BRIDGE_PASS fifo=true load_epoch=true detached=true freeze=true")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_OWNER_BRIDGE_FAIL: " + reason)
    quit(1)
