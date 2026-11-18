extends SceneTree
## PERF E: opt-in real same-seed direct/thread owner oracle. No synthetic ticks.
## Run headless as -s res://tests/p2_perf_e_real_direct_threaded_oracle.gd.
## This is bounded correctness evidence, NOT a CPU/FPS benchmark.
const NativeData = preload("res://scripts/native_data.gd")
const Direct = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const ThreadOwner = preload("res://scripts/sim/phase2/n158_real_owner_thread_probe.gd")
const Oracle = preload("res://scripts/sim/phase2/n158_checkpoint_parity_oracle.gd")
const Metrics = preload("res://scripts/sim/phase2/n158_worker_request_metrics.gd")
const TARGET: int = 100
const MILESTONES: Array[int] = [1, 20, 60, 100]
const REQUEST_TIMEOUT_MS: int = 20000
const TOTAL_BUDGET_MS: int = 180000
var _owner = null
var _start_ms: int = 0

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    _start_ms = Time.get_ticks_msec()
    if not _negative_oracles():
        _finish("negative oracle fixture rejected", false)
        return
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _finish("source seed unavailable", false)
        return
    var direct = Direct.new()
    if not direct.start_from_seed(seed):
        _finish("direct source boot failed", false)
        return
    _owner = ThreadOwner.new()
    if not _owner.launch(seed):
        _finish("thread owner launch failed", false)
        return
    var boot: Dictionary = await _answer(0, "boot")
    if not boot.get("ok", false) or int(boot.get("tick", -1)) != direct.tick_count:
        _finish("thread boot or source clock mismatch", false)
        return
    if not direct.queue_control("pause"):
        _finish("direct pause refused", false)
        return
    direct.advance_frame(0.0)
    var pause: Dictionary = await _command("pause")
    if not pause.get("ok", false):
        _finish("thread pause refused", false)
        return
    var timings: Array = []
    for tick in range(1, TARGET + 1):
        if not direct.queue_control("step", 1):
            _finish("direct step refused at " + str(tick), false)
            return
        var direct_start: int = Time.get_ticks_usec()
        direct.advance_frame(0.0)
        var direct_usec: int = Time.get_ticks_usec() - direct_start
        if direct.tick_count != tick or not direct.last_phase_failure().is_empty():
            _finish("direct paid tick failure " + str(tick), false)
            return
        var worker: Dictionary = await _command("step", {"count": 1})
        if not worker.get("ok", false) or int(worker.get("tick", -1)) != tick or (
                worker.get("advanced", false) != true):
            _finish("worker paid tick failure " + str(tick), false)
            return
        var timing: Dictionary = worker.get("timing", {})
        if not Metrics.accept_single_paid_tick_sample(timing.merged(
                {"after_tick": tick}), tick - 1, tick):
            _finish("invalid paid worker timing " + str(tick), false)
            return
        timings.append(timing.merged({"after_tick": tick,
            "direct_advance_wall_usec": direct_usec}))
        if timings.size() > 100:
            timings.pop_front()
        if MILESTONES.has(tick):
            var detached_direct: Dictionary = direct.checkpoint()
            var response: Dictionary = await _command("checkpoint")
            if not response.get("ok", false) or int(response.get("tick", -1)) != tick:
                _finish("checkpoint request failed " + str(tick), false)
                return
            var detached_worker: Dictionary = response.get("checkpoint", {})
            var parity: Dictionary = Oracle.compare(detached_direct, detached_worker)
            if not parity.get("equal", false):
                _finish("exact checkpoint divergence tick " + str(tick) +
                    " " + JSON.stringify(parity.get("difference", {})), false)
                return
            print("P2_PERF_E_DIRECT_THREAD_EXACT tick=", tick)
            if tick == 60:
                # Exercise actual N38-style runtime restore at a committed boundary.
                # Both owners restart from independent detached checkpoint trees.
                if not direct.restore_checkpoint(detached_direct.duplicate(true), seed):
                    _finish("direct N38 restart rejected", false)
                    return
                var restart: Dictionary = await _command("restore", {
                    "checkpoint": detached_worker.duplicate(true)})
                if not restart.get("ok", false) or int(restart.get("tick", -1)) != tick:
                    _finish("worker N38 restart rejected", false)
                    return
                var after_restart: Dictionary = await _command("checkpoint")
                if not after_restart.get("ok", false) or not Oracle.compare(
                        direct.checkpoint(), after_restart.get("checkpoint", {})).get("equal", false):
                    _finish("post-restart direct/thread divergence", false)
                    return
                print("P2_PERF_E_DIRECT_THREAD_RESTART_EXACT tick=", tick)
    var window: Dictionary = Metrics.bounded_paid_tick_window(timings, TARGET)
    if not window.get("complete", false) or int(window.get("observed_paid_ticks", -1)) != TARGET:
        _finish("missing 100 consecutive paid worker requests", false)
        return
    var direct_total: int = 0
    for row in timings:
        direct_total += int(row["direct_advance_wall_usec"])
    print("P2_PERF_E_DIRECT_THREAD_WINDOW ", JSON.stringify({
        "ticks": TARGET, "direct_advance_wall_avg_usec": float(direct_total) / TARGET,
        "worker_advance_wall_avg_usec": window["advance_wall_avg_usec"],
        "worker_request_wall_avg_usec": window["request_wall_avg_usec"],
        "worker_projection_wall_avg_usec": window["projection_wall_avg_usec"],
        "time_kind": "elapsed_wall_not_cpu", "performance_claim": false}))
    _finish("100 exact paid ticks; same-seed checkpoints", true)

func _command(kind: String, payload: Dictionary = {}) -> Dictionary:
    var ticket: int = _owner.submit(kind, payload)
    if ticket < 1:
        return {"ok": false, "error": "submit_rejected"}
    return await _answer(ticket, kind)

func _answer(ticket: int, kind: String) -> Dictionary:
    var began: int = Time.get_ticks_msec()
    while Time.get_ticks_msec() - began < REQUEST_TIMEOUT_MS and (
            Time.get_ticks_msec() - _start_ms < TOTAL_BUDGET_MS):
        var result: Dictionary = _owner.poll_answer()
        if not result.is_empty():
            if int(result.get("ticket", -1)) != ticket or str(result.get("kind", "")) != kind:
                return {"ok": false, "error": "out_of_order_or_wrong_ticket"}
            return result
        await process_frame
    return {"ok": false, "error": "bounded_owner_timeout"}

func _negative_oracles() -> bool:
    var expected: Dictionary = {"tick": 1, "native_production": {
        "tick": 1, "ledger": {"receipts": [1]}, "rng": [3, 7],
        "ships": [{"cargo": 4}]}}
    var equal: Dictionary = expected.duplicate(true)
    if not Oracle.compare(expected, equal).get("equal", false):
        return false
    var changed: Dictionary = expected.duplicate(true)
    changed["native_production"]["ships"][0]["cargo"] = 5
    if Oracle.compare(expected, changed).get("equal", true):
        return false
    changed = expected.duplicate(true)
    changed["native_production"]["rng"][1] = 8
    if Oracle.compare(expected, changed).get("equal", true):
        return false
    changed = expected.duplicate(true)
    changed["tick"] = 2
    if Oracle.compare(expected, changed).get("equal", true):
        return false
    if not Metrics.bounded_paid_tick_window([{
            "valid": true, "paid_ticks": 2, "after_tick": 100,
            "advance_wall_usec": 2, "projection_wall_usec": 1,
            "request_wall_usec": 3}], 100).is_empty():
        return false
    return true

func _finish(message: String, passed: bool) -> void:
    if _owner != null:
        _owner.close()
        _owner = null
    if passed:
        print("P2_PERF_E_DIRECT_THREAD_PASS ", message)
        quit(0)
    else:
        push_error("P2_PERF_E_DIRECT_THREAD_FAIL " + message)
        quit(1)
