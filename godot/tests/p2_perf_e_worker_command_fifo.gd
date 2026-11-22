extends SceneTree
## Isolated FIFO transport regression. No threaded backend enabled.
const FIFO = preload("res://scripts/sim/phase2/n158_worker_command_fifo.gd")

func _initialize() -> void:
    var q = FIFO.new()
    if q.enqueue("unknown") != -1 or q.enqueue("pause", {"bad": 1}) != -1:
        _fail("invalid command accepted")
        return
    if q.enqueue("speed", {"value": 0}) != -1 or q.enqueue("load", {"slot": RefCounted.new()}) != -1:
        _fail("invalid or live payload accepted")
        return
    var first: int = q.enqueue("pause")
    var second: int = q.enqueue("speed", {"value": 8.0})
    var third: int = q.enqueue("save", {"slot": "autosave"})
    if first != 1 or second != 2 or third != 3 or q.pending_count() != 3:
        _fail("tickets not monotonic")
        return
    if q.acknowledge(first, true) or q.read_ack(first) != {}:
        _fail("UI could acknowledge command before owner took it")
        return
    var a: Dictionary = q.take_next()
    var b: Dictionary = q.take_next()
    if a["id"] != first or b["id"] != second or b["kind"] != "speed":
        _fail("FIFO order changed")
        return
    b["payload"]["value"] = 99.0
    if q.acknowledge(second, true) or not q.acknowledge(first, true):
        _fail("out-of-order acknowledgement accepted")
        return
    if not q.acknowledge(second, false, "test failure"):
        _fail("failure acknowledgement rejected")
        return
    var ack: Dictionary = q.read_ack(second)
    if ack["success"] or ack["message"] != "test failure":
        _fail("failed command acknowledgement lost")
        return
    ack["message"] = "mutated"
    if q.read_ack(second)["message"] != "test failure":
        _fail("UI mutated acknowledgement")
        return
    var c: Dictionary = q.take_next()
    if c["id"] != third or not q.acknowledge(third, true):
        _fail("save command order broken")
        return
    if not q.take_next().is_empty() or q.pending_count() != 0:
        _fail("queue not empty after drain")
        return
    for i in range(FIFO.MAX_PENDING):
        if q.enqueue("step") < 0:
            _fail("bounded capacity rejected valid command")
            return
    if q.enqueue("step") != -1 or q.pending_count() != FIFO.MAX_PENDING:
        _fail("overflow was not rejected")
        return
    print("P2_PERF_E_WORKER_COMMAND_FIFO_PASS ordered=true bounded=true ack_order=true detached=true")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_WORKER_COMMAND_FIFO_FAIL: " + reason)
    quit(1)
