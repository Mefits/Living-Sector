extends SceneTree
const ADAPTER = preload("res://scripts/sim/phase2/n158_worker_execution_adapter.gd")
var _tick: int = 0
var _calls: int = 0
var _saved: int = 0
var _fail_tick: bool = false

func _initialize() -> void:
    var a = ADAPTER.new()
    assert(a.owner_configure(1.0))
    assert(a.ui_enqueue("step") > 0)
    var r: Dictionary = a.owner_pump(0.0, Callable(self, "_advance"), Callable(self, "_project"), Callable(self, "_persist"))
    assert(r.get("success") == true and r.get("advanced") == true)
    assert(_tick == 1 and _calls == 1)
    var frame: Dictionary = a.ui_read_frame()
    assert(frame["tick"] == 1 and frame["view"]["tick"] == 1)
    frame["view"]["tick"] = 999
    assert(a.ui_read_frame()["view"]["tick"] == 1)
    var save_ticket: int = a.ui_enqueue("save", {"slot": "test"})
    assert(save_ticket > 0)
    r = a.owner_pump(0.0, Callable(self, "_advance"), Callable(self, "_project"), Callable(self, "_persist"))
    assert(r["success"] and not r["advanced"] and _saved == 1)
    assert(a.ui_read_ack(save_ticket)["success"])
    var load_ticket: int = a.ui_enqueue("load", {"slot": "test"})
    r = a.owner_pump(0.0, Callable(self, "_advance"), Callable(self, "_project"), Callable(self, "_persist"))
    assert(a.ui_read_ack(load_ticket)["success"])
    assert(not a.ui_read_frame()["ready"])
    assert(a.ui_read_frame()["epoch"] == 1)
    assert(a.ui_enqueue("step") > 0)
    _fail_tick = true
    r = a.owner_pump(0.0, Callable(self, "_advance"), Callable(self, "_project"))
    assert(not r["success"] and r["error"] == "authoritative_tick_failed")
    assert(not a.ui_read_frame()["ready"])
    assert(a.ui_enqueue("step") == -1)
    print("P2_PERF_E_EXECUTION_ADAPTER_BOUNDARY_PASS")
    quit()

func _advance() -> Dictionary:
    _calls += 1
    if _fail_tick:
        return {"success": false, "tick": _tick}
    _tick += 1
    return {"success": true, "tick": _tick}

func _project(tick: int) -> Dictionary:
    return {"tick": tick, "ships": []}

func _persist(kind: String, slot: String) -> bool:
    if slot != "test":
        return false
    if kind == "save":
        _saved += 1
    elif kind == "load":
        _tick = 0
    return true
