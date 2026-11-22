extends SceneTree
## E: REAL Thread.start() N158 with the frozen seed, not a mock callback.
## A single authoritative worker-owned runner is compared to a separate
## direct reference runner after the same paid commands and N38 save/restart.
const NativeData = preload("res://scripts/native_data.gd")
const Runner = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Saves = preload("res://scripts/sim/save_state.gd")
const N38Guard = preload("res://scripts/sim/phase2/unified_native_save_roundtrip_guard.gd")
const Worker = preload("res://scripts/sim/phase2/n158_real_owner_thread_probe.gd")

var _worker = Worker.new()
var _seed: Dictionary = {}

func _initialize() -> void:
    _seed = NativeData.load_current_world()
    if _seed.has("error"):
        _fail("frozen Rust seed not available")
        return
    var direct = Runner.new()
    if not direct.start_from_seed(_seed) or not _worker.launch(_seed):
        _fail("direct or actual owner thread boot failed")
        return
    var boot: Dictionary = _wait_for(0)
    if not boot.get("ok", false) or int(boot.get("ships", -1)) != 24:
        _fail("worker did not boot one authentic N158 with 24 ships: " + str(boot))
        return
    if not _compare(direct, "seed"):
        return
    if not _control(direct, "pause"):
        return
    if not _control(direct, "speed", {"value": 8.0}):
        return
    if not _control(direct, "step", {"count": 1}):
        return
    if not _control(direct, "step", {"count": 4}):
        return
    if direct.tick_count != 5 or not direct.last_phase_failure().is_empty():
        _fail("authentic five-tick paid source sequence failed")
        return
    if _worker.submit("unknown") != -1 or (
            _worker.submit("step", {"count": 0}) != -1) or (
            _worker.submit("speed", {"value": -2.0}) != -1) or (
            _worker.submit("save", {"path": "res://unsafe"}) != -1) or (
            _worker.submit("checkpoint", {"obj": RefCounted.new()}) != -1):
        _fail("invalid or live-reference command entered worker FIFO")
        return
    var save_path: String = "user://tests/p2-e-real-owner-" + str(Time.get_ticks_usec()) + ".json"
    if not _execute("save", {"path": save_path}):
        return
    var saved: Dictionary = direct.checkpoint()
    if not _control(direct, "step", {"count": 1}):
        return
    var ticket: int = _worker.submit("load", {"path": save_path})
    if ticket <= 0:
        _fail("load command refused")
        return
    var outcome: Dictionary = _wait_for(ticket)
    if not outcome.get("ok", false):
        _fail("worker N38 save/load failed: " + str(outcome))
        return
    var loaded: Dictionary = Saves.load_runner(direct, _seed, save_path)
    if not loaded.get("ok", false) or direct.tick_count != 5:
        _fail("direct N38 load rejected/tick mismatch: " + str(loaded)
            + " tick=" + str(direct.tick_count))
        return
    var after_load: Dictionary = direct.checkpoint()
    # Existing N38 on-disk codec accepts exact integer-to-float promotion
    # for source counters (e.g. research_directors.stations), but never
    # rounding or mutation of money, stock, cargo, contracts or receipts.
    # Use the SAME authoritative check as production SaveState instead of
    # incorrectly requiring a byte-identical pre/post JSON Variant type.
    var n38_parity: Dictionary = N38Guard.verify_authoritative_frame(saved, after_load)
    if not n38_parity.get("ok", false):
        _fail("direct authoritative N38 frame drift: " + str(n38_parity)
            + " first=" + _first_difference(saved, after_load, "checkpoint", 0))
        return
    if not _compare(direct, "N38 restart at tick5"):
        return
    if not _control(direct, "step", {"count": 1}):
        return
    # Exercise the SAME real clock.consume_frame(delta) on both owners,
    # including sub-tick frames and a frame large enough to commit paid N39.
    if not _control(direct, "resume"):
        return
    var frame_deltas: Array[float] = [0.02, 0.04, 0.08, 0.125, 0.125]
    for frame_delta in frame_deltas:
        direct.advance_frame(frame_delta)
        if not direct.last_phase_failure().is_empty():
            _fail("direct N158 frame phase rejected")
            return
        if not _execute("frame", {"delta": frame_delta, "view": true,
                "observer": true}):
            return
        if not _compare(direct, "real GUI frame %.3f" % frame_delta):
            return
    # Illegal catch-up deltas, live references and dangerous save paths are
    # rejected before the sole N158 worker can examine them.
    if _worker.submit("frame", {"delta": -0.1}) != -1 or (
            _worker.submit("frame", {"delta": 0.4}) != -1) or (
            _worker.submit("frame", {"delta": 0.1, "view": "yes"}) != -1):
        _fail("invalid worker GUI frame input admitted")
        return
    var corrupt_ticket: int = _worker.submit("restore", {"checkpoint": {"native_production": {}}})
    var corrupt: Dictionary = _wait_for(corrupt_ticket)
    if corrupt.get("ok", true) or not str(corrupt.get("error", "")).contains("restore_rejected"):
        _fail("forged N38 checkpoint accepted")
        return
    var frozen_ticket: int = _worker.submit("step", {"count": 1})
    var frozen: Dictionary = _wait_for(frozen_ticket)
    if frozen.get("ok", true) or frozen.get("error") != "authoritative_owner_frozen":
        _fail("failed restore did not freeze single owner")
        return
    _worker.close()
    print("P2_PERF_E_REAL_OWNER_N158_PARITY_PASS paid_ticks=9 frames=5 checkpoint=exact n38_restart=true forged_restore_frozen=true")
    quit(0)

func _control(direct, kind: String, payload: Dictionary = {}) -> bool:
    var direct_value: Variant = null
    if kind == "speed":
        direct_value = payload["value"]
    elif kind == "step":
        direct_value = payload["count"]
    if not direct.queue_control(kind, direct_value):
        _fail("direct control rejected " + kind)
        return false
    direct.advance_frame(0.0)
    if not direct.last_phase_failure().is_empty():
        _fail("direct N158 phase rejected " + kind)
        return false
    if not _execute(kind, payload):
        return false
    return _compare(direct, kind)

func _execute(kind: String, payload: Dictionary = {}) -> bool:
    var ticket: int = _worker.submit(kind, payload)
    if ticket <= 0:
        _fail("worker command rejected " + kind)
        return false
    var outcome: Dictionary = _wait_for(ticket)
    if not outcome.get("ok", false):
        _fail("worker " + kind + " failed: " + str(outcome))
        return false
    return true

func _compare(direct, label: String) -> bool:
    var ticket: int = _worker.submit("checkpoint")
    if ticket <= 0:
        _fail("worker checkpoint queue rejected at " + label)
        return false
    var outcome: Dictionary = _wait_for(ticket)
    if not outcome.get("ok", false) or not (outcome.get("checkpoint") is Dictionary):
        _fail("worker checkpoint missing at " + label)
        return false
    var actual: Dictionary = outcome["checkpoint"]
    var expected: Dictionary = direct.checkpoint()
    if actual != expected:
        _fail("FULL authoritative N158/N39/N9/BT/RNG checkpoint parity drift at "
            + label + " worker_tick=" + str(outcome.get("tick"))
            + " direct_tick=" + str(direct.tick_count))
        return false
    actual.clear()
    # A caller may mutate a returned detached snapshot. It must not
    # affect the unique worker's authoritative Ledger/World.
    var again_ticket: int = _worker.submit("checkpoint")
    var again: Dictionary = _wait_for(again_ticket)
    if not again.get("ok", false) or again.get("checkpoint") != expected:
        _fail("checkpoint response leaked mutable aliases at " + label)
        return false
    return true

func _wait_for(ticket: int) -> Dictionary:
    var deadline: int = Time.get_ticks_msec() + 20000
    while Time.get_ticks_msec() < deadline:
        var item: Dictionary = _worker.poll_answer()
        if not item.is_empty():
            if int(item.get("ticket", -1)) != ticket:
                _fail("out-of-order owner response")
                return {}
            return item
        OS.delay_msec(5)
    _fail("worker response timeout " + str(ticket))
    return {}

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_REAL_OWNER_N158_PARITY_FAIL: " + reason)
    _worker.close()
    quit(1)

func _first_difference(left: Variant, right: Variant, path: String, depth: int) -> String:
    if depth > 80:
        return path + " depth"
    if typeof(left) != typeof(right):
        return path + " type=" + str(typeof(left)) + "/" + str(typeof(right))
    if left is Dictionary:
        if left.size() != right.size():
            return path + " size=" + str(left.size()) + "/" + str(right.size())
        for key in left:
            if not right.has(key):
                return path + " missing=" + str(key)
            var nested: String = _first_difference(left[key], right[key],
                path + "/" + str(key), depth + 1)
            if not nested.is_empty():
                return nested
        return ""
    if left is Array:
        if left.size() != right.size():
            return path + " size=" + str(left.size()) + "/" + str(right.size())
        for i in range(left.size()):
            var nested: String = _first_difference(left[i], right[i],
                path + "/" + str(i), depth + 1)
            if not nested.is_empty():
                return nested
        return ""
    return "" if left == right else path + " mismatch:" + str(left) + "/" + str(right)
