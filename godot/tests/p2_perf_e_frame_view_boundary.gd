extends SceneTree
## Pure boundary regression; does not claim GUI FPS or N158 parity.
const Mailbox = preload("res://scripts/sim/phase2/n158_committed_frame_view.gd")

func _initialize() -> void:
    var mailbox = Mailbox.new()
    var source: Dictionary = {
        "clock": {"paused": false, "speed": 8.0},
        "ships": [{"id": "source-ship", "cargo": {"ore": 4}}],
        "status": "committed"}
    if not mailbox.publish_committed(10, source):
        _fail("initial completed frame refused")
        return
    source["ships"][0]["cargo"]["ore"] = 999
    source["clock"]["paused"] = true
    var first: Dictionary = mailbox.read_latest()
    if first["tick"] != 10 or not first["ready"] or (
            first["view"]["ships"][0]["cargo"]["ore"] != 4) or (
            first["view"]["clock"]["paused"] != false):
        _fail("producer alias escaped")
        return
    first["view"]["ships"][0]["cargo"]["ore"] = -10
    first["view"]["clock"]["speed"] = -1.0
    var second: Dictionary = mailbox.read_latest()
    if second["view"]["ships"][0]["cargo"]["ore"] != 4 or (
            second["view"]["clock"]["speed"] != 8.0):
        _fail("consumer alias escaped")
        return
    if mailbox.publish_committed(10, {"status": "duplicate"}) or (
            mailbox.publish_committed(9, {"status": "stale"})):
        _fail("out-of-order committed frame accepted")
        return
    if mailbox.publish_committed(11, {"unsafe": RefCounted.new()}):
        _fail("live object crossed detached boundary")
        return
    if mailbox.read_latest()["tick"] != 10:
        _fail("rejected frame changed committed state")
        return
    mailbox.reset_after_load()
    var cleared: Dictionary = mailbox.read_latest()
    if cleared["ready"] or cleared["tick"] != -1 or cleared["epoch"] != 1:
        _fail("load epoch did not invalidate stale projection")
        return
    if not mailbox.publish_committed(3, {"status": "restored"}):
        _fail("legitimate earlier save tick refused")
        return
    var restored: Dictionary = mailbox.read_latest()
    if restored["tick"] != 3 or restored["epoch"] != 1 or (
            restored["view"]["status"] != "restored"):
        _fail("post-load committed projection incorrect")
        return
    print("P2_PERF_E_FRAME_VIEW_BOUNDARY_PASS producer_detached=true consumer_detached=true stale_rejected=true object_rejected=true load_epoch=true")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_FRAME_VIEW_BOUNDARY_FAIL: " + reason)
    quit(1)
