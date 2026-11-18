extends SceneTree
## PERF E: opt-in real same-seed direct/thread owner oracle. No synthetic ticks.
## Run headless as -s res://tests/p2_perf_e_real_direct_threaded_oracle.gd.
## This is bounded correctness evidence, NOT a CPU/FPS benchmark.
const NativeData = preload("res://scripts/native_data.gd")
const Direct = preload("res://scripts/sim/phase2/n158_timed_phase_probe.gd")
const ThreadOwner = preload("res://scripts/sim/phase2/n158_real_owner_thread_probe.gd")
const Oracle = preload("res://scripts/sim/phase2/n158_checkpoint_parity_oracle.gd")
const Metrics = preload("res://scripts/sim/phase2/n158_worker_request_metrics.gd")
const Acceptance = preload("res://scripts/sim/phase2/n158_direct_threaded_acceptance.gd")
const DEFAULT_TARGET: int = 100
const LATE_TARGET: int = 300
const EXTENDED_TARGET: int = 900
const EXTENDED_MILESTONES: Array[int] = [600, 900]
const MILESTONES: Array[int] = [1, 20, 60, 100, 200, 300]
const REQUEST_TIMEOUT_MS: int = 20000
const TOTAL_BUDGET_MS: int = 180000
const EXTENDED_BUDGET_MS: int = 480000
const LATE_WINDOWS: Array[int] = [100, 300, 600, 900]
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
    # Explicit opt-in: longer parity probe never runs in default 100-tick mode.
    var mode: String = OS.get_environment("LS_E_LATE_DIRECT_THREAD")
    var target: int = (EXTENDED_TARGET if mode == "900" else (
        LATE_TARGET if mode == "1" else DEFAULT_TARGET))
    var budget_ms: int = (EXTENDED_BUDGET_MS if target == EXTENDED_TARGET
        else TOTAL_BUDGET_MS)
    var timings: Array = []
    var early_window: Dictionary = {}
    var last_window: Dictionary = {}
    var early_sizes: Dictionary = {}
    var early_source_counts: Dictionary = {}
    var previous_sizes: Dictionary = {}
    var previous_source_counts: Dictionary = {}
    var previous_window: Dictionary = {}
    var observation_samples: Array = []
    var phase_reports: Array = []
    for tick in range(1, target + 1):
        if Time.get_ticks_msec() - _start_ms >= budget_ms:
            _finish("bounded wall budget exceeded before paid tick " + str(tick), false)
            return
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
        # Only exact complete 100-paid-tick windows; never divide a multi-tick
        # request or compare overlapping windows as independent growth evidence.
        if LATE_WINDOWS.has(tick) and tick <= target:
            var window: Dictionary = Acceptance.summarize_window(tick, timings)
            if not window.get("accepted", false):
                _finish("invalid paid window at " + str(tick) + ": " + str(window), false)
                return
            if tick == 100:
                early_window = window.duplicate(true)
            last_window = window.duplicate(true)
            if not previous_window.is_empty():
                var window_delta: Dictionary = Acceptance.compare_late_windows(
                    previous_window, window)
                if not window_delta.get("accepted", false):
                    _finish("adjacent window attribution rejected " + str(window_delta), false)
                    return
                print("P2_PERF_E_DIRECT_THREAD_ADJACENT_WINDOW ", JSON.stringify(window_delta))
            previous_window = window.duplicate(true)
            print("P2_PERF_E_DIRECT_THREAD_WINDOW ", JSON.stringify(window))
        if MILESTONES.has(tick) or (target == EXTENDED_TARGET and
                EXTENDED_MILESTONES.has(tick)):
            var direct_checkpoint_started: int = Time.get_ticks_usec()
            var detached_direct: Dictionary = direct.checkpoint()
            var direct_checkpoint_usec: int = Time.get_ticks_usec() - direct_checkpoint_started
            var worker_checkpoint_started: int = Time.get_ticks_usec()
            var response: Dictionary = await _command("checkpoint")
            var worker_checkpoint_request_usec: int = Time.get_ticks_usec() - worker_checkpoint_started
            if not response.get("ok", false) or int(response.get("tick", -1)) != tick:
                _finish("checkpoint request failed " + str(tick), false)
                return
            var detached_worker: Dictionary = response.get("checkpoint", {})
            var parity: Dictionary = Acceptance.verify_boundary(tick, detached_direct, response)
            if not parity.get("accepted", false):
                _finish("exact checkpoint divergence tick " + str(tick) +
                    " " + JSON.stringify(parity.get("difference", {})), false)
                return
            var observation: Dictionary = Acceptance.checkpoint_observation_sample(
                tick, direct_checkpoint_usec, worker_checkpoint_request_usec,
                detached_direct, response)
            if not observation.get("accepted", false):
                _finish("checkpoint observation invalid " + str(tick) +
                    " " + JSON.stringify(observation), false)
                return
            observation_samples.append(observation)
            print("P2_PERF_E_DIRECT_THREAD_EXACT tick=", tick)
            if LATE_WINDOWS.has(tick) and tick <= target:
                var direct_phases: Dictionary = direct.paid_phase_distribution(tick)
                var paired_response: Dictionary = response.duplicate(true)
                paired_response["paid_phase_window"] = worker.get("paid_phase_window", {})
                var paid_phase_gate: Dictionary = Acceptance.verify_paid_phase_pair(
                    tick, detached_direct, paired_response, direct_phases, last_window)
                if not paid_phase_gate.get("accepted", false):
                    _finish("paid phase attribution failed " + str(tick) +
                        " " + JSON.stringify(paid_phase_gate), false)
                    return
                phase_reports.append({"tick": tick,
                    "phase_comparison": paid_phase_gate["phase_comparison"]})
                print("P2_PERF_E_DIRECT_THREAD_PHASES ",
                    JSON.stringify(paid_phase_gate))
                var size_boundary: Dictionary = Acceptance.compare_size_boundary(
                    tick, detached_direct, detached_worker)
                if not size_boundary.get("accepted", false):
                    _finish("authoritative size divergence tick " + str(tick) +
                        " " + JSON.stringify(size_boundary), false)
                    return
                var source_boundary: Dictionary = Acceptance.compare_source_growth_boundary(
                    tick, detached_direct, detached_worker)
                if not source_boundary.get("accepted", false):
                    _finish("N9/events source size divergence tick " + str(tick) +
                        " " + JSON.stringify(source_boundary), false)
                    return
                print("P2_PERF_E_DIRECT_THREAD_N9_EVENTS ", JSON.stringify(source_boundary))
                if tick == 100:
                    early_source_counts = source_boundary.duplicate(true)
                if not previous_source_counts.is_empty():
                    var source_growth: Dictionary = Acceptance.compare_source_growth(
                        previous_source_counts, source_boundary)
                    if not source_growth.get("accepted", false):
                        _finish("invalid N9/events growth " + JSON.stringify(source_growth), false)
                        return
                    print("P2_PERF_E_DIRECT_THREAD_N9_EVENTS_GROWTH ",
                        JSON.stringify(source_growth))
                previous_source_counts = source_boundary.duplicate(true)
                print("P2_PERF_E_DIRECT_THREAD_SIZE ", JSON.stringify(size_boundary))
                if tick == 100:
                    early_sizes = size_boundary.duplicate(true)
                if not previous_sizes.is_empty():
                    var size_growth: Dictionary = Acceptance.compare_size_growth(
                        previous_sizes, size_boundary)
                    if not size_growth.get("accepted", false):
                        _finish("invalid direct/thread size growth " +
                            JSON.stringify(size_growth), false)
                        return
                    print("P2_PERF_E_DIRECT_THREAD_SIZE_GROWTH ",
                        JSON.stringify(size_growth))
                previous_sizes = size_boundary.duplicate(true)
            if tick == target:
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
    var expected_observations: Array[int] = []
    for milestone in MILESTONES:
        if milestone <= target:
            expected_observations.append(milestone)
    if target == EXTENDED_TARGET:
        expected_observations.append_array(EXTENDED_MILESTONES)
    var observation_report: Dictionary = Acceptance.summarize_checkpoint_observations(
        observation_samples, expected_observations)
    if not observation_report.get("accepted", false):
        _finish("checkpoint observation coverage invalid " + JSON.stringify(observation_report), false)
        return
    print("P2_PERF_E_CHECKPOINT_OBSERVATION_COST ", JSON.stringify(observation_report))
    print("P2_PERF_E_PHASE_WINDOW_COVERAGE ", JSON.stringify(phase_reports))
    if last_window.is_empty():
        _finish("missing final complete paid window", false)
        return
    if target >= LATE_TARGET:
        var growth: Dictionary = Acceptance.compare_late_windows(early_window, last_window)
        if not growth.get("accepted", false):
            _finish("late window attribution rejected: " + str(growth), false)
            return
        print("P2_PERF_E_DIRECT_THREAD_LATE_GROWTH ", JSON.stringify(growth))
    _finish(str(target) + " exact paid ticks; same-seed checkpoints", true)

func _command(kind: String, payload: Dictionary = {}) -> Dictionary:
    var ticket: int = _owner.submit(kind, payload)
    if ticket < 1:
        return {"ok": false, "error": "submit_rejected"}
    return await _answer(ticket, kind)

func _answer(ticket: int, kind: String) -> Dictionary:
    var began: int = Time.get_ticks_msec()
    while Time.get_ticks_msec() - began < REQUEST_TIMEOUT_MS and (
            Time.get_ticks_msec() - _start_ms < (EXTENDED_BUDGET_MS if
                OS.get_environment("LS_E_LATE_DIRECT_THREAD") == "900" else TOTAL_BUDGET_MS)):
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
    var good_boundary: Dictionary = {"ok": true, "tick": 1,
        "checkpoint": expected.duplicate(true)}
    if not Acceptance.verify_boundary(1, expected, good_boundary).get("accepted", false):
        return false
    var bad_boundary: Dictionary = good_boundary.duplicate(true)
    bad_boundary["tick"] = 2
    if Acceptance.verify_boundary(1, expected, bad_boundary).get("accepted", false):
        return false
    bad_boundary = good_boundary.duplicate(true)
    bad_boundary["checkpoint"]["native_production"]["ledger"]["receipts"][0] = 2
    if Acceptance.verify_boundary(1, expected, bad_boundary).get("accepted", false):
        return false
    bad_boundary = good_boundary.duplicate(true)
    bad_boundary.erase("checkpoint")
    if Acceptance.verify_boundary(1, expected, bad_boundary).get("accepted", false):
        return false
    if Acceptance.summarize_window(100, [{
            "valid": true, "paid_ticks": 2, "after_tick": 100,
            "advance_wall_usec": 2, "projection_wall_usec": 1,
            "request_wall_usec": 3}]).get("accepted", false):
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
