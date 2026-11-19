extends SceneTree
## PERF E negative regression: UI slot identifiers cannot become paths.
const FIFO = preload("res://scripts/sim/phase2/n158_worker_command_fifo.gd")

func _initialize() -> void:
    var queue = FIFO.new()
    var forbidden: Array[String] = ["../save", "..", "slot/name", "slot\\name",
        "user://save", "a b", "a.b", "line\nfeed", "ümlaut", "a".repeat(129)]
    for token in forbidden:
        if queue.enqueue("save", {"slot": token}) != -1:
            _fail("unsafe save slot accepted: " + token)
            return
        if queue.enqueue("load", {"slot": token}) != -1:
            _fail("unsafe load slot accepted: " + token)
            return
    var valid: Array[String] = ["autosave", "save_01", "SLOT-9", "a".repeat(128)]
    for token in valid:
        var ticket: int = queue.enqueue("save", {"slot": token})
        if ticket <= 0:
            _fail("safe slot rejected: " + token)
            return
        var command: Dictionary = queue.take_next()
        if command.get("id") != ticket or command.get("payload", {}).get("slot") != token:
            _fail("slot payload or FIFO ticket changed")
            return
        if not queue.acknowledge(ticket, true):
            _fail("safe slot acknowledgement failed")
            return
    if queue.pending_count() != 0:
        _fail("slot queue not drained")
        return
    print("P2_PERF_E_FIFO_SLOT_TOKEN_BOUNDARY_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_FIFO_SLOT_TOKEN_BOUNDARY_FAIL: " + reason)
    quit(1)
