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
const PhaseGrowth = preload("res://scripts/sim/phase2/n158_phase_growth_acceptance.gd")
const CallsiteCosts = preload("res://scripts/sim/phase2/n158_callsite_cost_acceptance.gd")
const ObservationCosts = preload("res://scripts/sim/phase2/n158_observation_cost_acceptance.gd")
const SizePhase = preload("res://scripts/sim/phase2/n158_size_phase_attribution.gd")
const CheckpointBytes = preload("res://scripts/sim/phase2/n158_checkpoint_byte_probe.gd")
const ResourceProbe = preload("res://scripts/sim/phase2/n158_paid_window_resource_probe.gd")
const PairedDrift = preload("res://scripts/sim/phase2/n158_paired_paid_tick_drift.gd")
const RestartContinuation = preload("res://scripts/sim/phase2/n158_post_restart_paid_continuation.gd")
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
    var first_resource_window: Dictionary = {}
    var previous_resource_window: Dictionary = {}
    var first_paired_window: Dictionary = {}
    var previous_paired_window: Dictionary = {}
    var observation_samples: Array = []
    var observation_callsite_samples: Array = []
    var checkpoint_byte_samples: Array = []
    var previous_observation_cost: Dictionary = {}
    var phase_reports: Array = []
    var first_phase_window: Dictionary = {}
    var previous_phase_window: Dictionary = {}
    var previous_joint_sizes: Dictionary = {}
    var previous_joint_sources: Dictionary = {}
    var previous_joint_phase: Dictionary = {}
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
            # Paired per-tick comparison uses the same real 100 paid steps;
            # exact checkpoint gate below authorizes publishing the result.
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
            var parity_started: int = Time.get_ticks_usec()
            var parity: Dictionary = Acceptance.verify_boundary(tick, detached_direct, response)
            var parity_usec: int = Time.get_ticks_usec() - parity_started
            if not parity.get("accepted", false):
                _finish("exact checkpoint divergence tick " + str(tick) +
                    " " + JSON.stringify(parity.get("difference", {})), false)
                return
            if LATE_WINDOWS.has(tick) and tick <= target:
                var paired: Dictionary = PairedDrift.accept(tick, timings, parity)
                if not paired.get("accepted", false):
                    _finish("paired paid tick drift rejected " + JSON.stringify(paired), false)
                    return
                if tick == 100:
                    first_paired_window = paired.duplicate(true)
                if not previous_paired_window.is_empty():
                    var paired_adjacent: Dictionary = PairedDrift.compare(
                        previous_paired_window, paired)
                    if not paired_adjacent.get("accepted", false):
                        _finish("paired drift growth rejected " + JSON.stringify(paired_adjacent), false)
                        return
                    print("P2_PERF_E_PAIRED_ADJACENT ", JSON.stringify(paired_adjacent))
                previous_paired_window = paired.duplicate(true)
                print("P2_PERF_E_PAIRED_WINDOW ", JSON.stringify(paired))
                # Same process hosts both owners: allocator bytes are combined,
                # never attributed to one worker or reported as OS RSS.
                var resource_window: Dictionary = ResourceProbe.measure(
                    tick, timings, parity,
                    int(Performance.get_monitor(Performance.MEMORY_STATIC)),
                    int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)))
                if not resource_window.get("accepted", false):
                    _finish("paid resource window rejected " + JSON.stringify(resource_window), false)
                    return
                if tick == 100:
                    first_resource_window = resource_window.duplicate(true)
                if not previous_resource_window.is_empty():
                    var resource_delta: Dictionary = ResourceProbe.compare(
                        previous_resource_window, resource_window)
                    if not resource_delta.get("accepted", false):
                        _finish("paid resource growth rejected " + JSON.stringify(resource_delta), false)
                        return
                    print("P2_PERF_E_RESOURCE_ADJACENT ", JSON.stringify(resource_delta))
                previous_resource_window = resource_window.duplicate(true)
                print("P2_PERF_E_RESOURCE_WINDOW ", JSON.stringify(resource_window))
            # Encode only already-detached, exact-parity-approved boundaries.
            # This diagnostic is outside both paid tick timing windows.
            var encoded: Dictionary = CheckpointBytes.measure(
                tick, detached_direct, detached_worker, parity)
            if not encoded.get("accepted", false):
                _finish("detached checkpoint byte probe failed " + str(tick) +
                    " " + JSON.stringify(encoded), false)
                return
            checkpoint_byte_samples.append(encoded)
            var observation: Dictionary = Acceptance.checkpoint_observation_sample(
                tick, direct_checkpoint_usec, worker_checkpoint_request_usec,
                detached_direct, response)
            if not observation.get("accepted", false):
                _finish("checkpoint observation invalid " + str(tick) +
                    " " + JSON.stringify(observation), false)
                return
            observation_samples.append(observation)
            var size_oracle_usec: int = 0
            var source_oracle_usec: int = 0
            var size_cost_gate: Dictionary = {}
            var source_cost_gate: Dictionary = {}
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
                var callsite_gate: Dictionary = CallsiteCosts.verify(tick,
                    parity, direct.paid_callsite_costs(tick),
                    worker.get("paid_callsite_costs", {}), direct_phases,
                    worker.get("paid_phase_window", {}))
                if not callsite_gate.get("accepted", false):
                    _finish("paid callsite attribution failed " + str(tick) +
                        " " + JSON.stringify(callsite_gate), false)
                    return
                print("P2_PERF_E_CALLSITE_COSTS ", JSON.stringify(callsite_gate))
                # Compare only exact checkpoint-gated, detached phase evidence.
                # Normalize by real calls and active ticks: cadence changes are
                # not misreported as an increase in per-call execution cost.
                var phase_window: Dictionary = PhaseGrowth.accept_window(
                    tick, paid_phase_gate)
                if not phase_window.get("accepted", false):
                    _finish("phase growth boundary rejected " + str(phase_window), false)
                    return
                if tick == 100:
                    first_phase_window = phase_window.duplicate(true)
                if not previous_phase_window.is_empty():
                    var adjacent_phases: Dictionary = PhaseGrowth.compare(
                        previous_phase_window, phase_window)
                    if not adjacent_phases.get("accepted", false):
                        _finish("phase growth attribution rejected " +
                            JSON.stringify(adjacent_phases), false)
                        return
                    print("P2_PERF_E_PHASE_ADJACENT_GROWTH ",
                        JSON.stringify(adjacent_phases))
                previous_phase_window = phase_window.duplicate(true)
                phase_reports.append({"tick": tick,
                    "phase_comparison": paid_phase_gate["phase_comparison"]})
                print("P2_PERF_E_DIRECT_THREAD_PHASES ",
                    JSON.stringify(paid_phase_gate))
                var size_oracle_started: int = Time.get_ticks_usec()
                var size_boundary: Dictionary = Acceptance.compare_size_boundary(
                    tick, detached_direct, detached_worker)
                if not size_boundary.get("accepted", false):
                    _finish("authoritative size divergence tick " + str(tick) +
                        " " + JSON.stringify(size_boundary), false)
                    return
                size_oracle_usec = Time.get_ticks_usec() - size_oracle_started
                size_cost_gate = size_boundary
                var source_oracle_started: int = Time.get_ticks_usec()
                var source_boundary: Dictionary = Acceptance.compare_source_growth_boundary(
                    tick, detached_direct, detached_worker)
                source_oracle_usec = Time.get_ticks_usec() - source_oracle_started
                source_cost_gate = source_boundary
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
                if not previous_joint_sizes.is_empty():
                    var phase_delta: Dictionary = PhaseGrowth.compare(
                        previous_joint_phase, phase_window)
                    var world_delta: Dictionary = Acceptance.compare_size_growth(
                        previous_joint_sizes, size_boundary)
                    var source_delta: Dictionary = Acceptance.compare_source_growth(
                        previous_joint_sources, source_boundary)
                    var joint: Dictionary = SizePhase.compare(
                        phase_delta, world_delta, source_delta)
                    if not joint.get("accepted", false):
                        _finish("joint size/phase attribution rejected " +
                            JSON.stringify(joint), false)
                        return
                    print("P2_PERF_E_SIZE_PHASE_GROWTH ", JSON.stringify(joint))
                previous_joint_sizes = size_boundary.duplicate(true)
                previous_joint_sources = source_boundary.duplicate(true)
                previous_joint_phase = phase_window.duplicate(true)
                previous_sizes = size_boundary.duplicate(true)
            var cost_row: Dictionary = ObservationCosts.sample(tick, {
                "direct_checkpoint": direct_checkpoint_usec,
                "worker_checkpoint_request": worker_checkpoint_request_usec,
                "exact_parity_oracle": parity_usec,
                "size_oracle": size_oracle_usec,
                "n9_event_oracle": source_oracle_usec}, parity, size_cost_gate, source_cost_gate)
            if not cost_row.get("accepted", false):
                _finish("observation callsite attribution failed " + JSON.stringify(cost_row), false)
                return
            observation_callsite_samples.append(cost_row)
            if tick in LATE_WINDOWS:
                if not previous_observation_cost.is_empty():
                    var cost_growth: Dictionary = ObservationCosts.compare_growth(
                        previous_observation_cost, cost_row)
                    if not cost_growth.get("accepted", false):
                        _finish("observation growth rejected " + JSON.stringify(cost_growth), false)
                        return
                    print("P2_PERF_E_OBSERVATION_CALLSITE_GROWTH ", JSON.stringify(cost_growth))
                previous_observation_cost = cost_row.duplicate(true)
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
                # A restored checkpoint matching itself is insufficient: prove
                # three real subsequent paid steps preserve N9/World/RNG/BT.
                # This is intentionally outside the pre-restart 100-tick windows.
                var continuation_rows: Array = []
                for resumed_tick in range(tick + 1, tick + 4):
                    if not direct.queue_control("step", 1):
                        _finish("post-restart direct step refused " + str(resumed_tick), false)
                        return
                    var resumed_started: int = Time.get_ticks_usec()
                    direct.advance_frame(0.0)
                    var resumed_direct_usec: int = Time.get_ticks_usec() - resumed_started
                    if not direct.last_phase_failure().is_empty():
                        _finish("post-restart direct phase failed " + str(resumed_tick), false)
                        return
                    var resumed_worker_started: int = Time.get_ticks_usec()
                    var resumed_worker: Dictionary = await _command("step", {"count": 1})
                    var resumed_worker_request_usec: int = (
                        Time.get_ticks_usec() - resumed_worker_started)
                    var resumed_checkpoint: Dictionary = await _command("checkpoint")
                    var resumed_direct_checkpoint: Dictionary = direct.checkpoint()
                    var resumed_gate: Dictionary = RestartContinuation.accept_step(
                        resumed_tick - 1, direct.tick_count, resumed_direct_checkpoint,
                        resumed_worker, resumed_checkpoint, resumed_direct_usec,
                        resumed_worker_request_usec)
                    if not resumed_gate.get("accepted", false):
                        _finish("post-restart paid parity failed tick " + str(resumed_tick) +
                            " " + JSON.stringify(resumed_gate), false)
                        return
                    continuation_rows.append(resumed_gate)
                var continuation: Dictionary = RestartContinuation.summarize(
                    tick, continuation_rows)
                if not continuation.get("accepted", false):
                    _finish("post-restart paid coverage failed " +
                        JSON.stringify(continuation), false)
                    return
                print("P2_PERF_E_POST_RESTART_PAID_CONTINUATION ",
                    JSON.stringify(continuation))
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
    var checkpoint_bytes: Dictionary = CheckpointBytes.summarize(
        checkpoint_byte_samples, expected_observations)
    if not checkpoint_bytes.get("accepted", false):
        _finish("detached checkpoint byte coverage failed " +
            JSON.stringify(checkpoint_bytes), false)
        return
    print("P2_PERF_E_DETACHED_CHECKPOINT_BYTES ", JSON.stringify(checkpoint_bytes))
    var observation_calls: Dictionary = ObservationCosts.summarize(
        observation_callsite_samples, expected_observations)
    if not observation_calls.get("accepted", false):
        _finish("observation callsite coverage invalid " + JSON.stringify(observation_calls), false)
        return
    print("P2_PERF_E_OBSERVATION_CALLSITES ", JSON.stringify(observation_calls))
    print("P2_PERF_E_PHASE_WINDOW_COVERAGE ", JSON.stringify(phase_reports))
    if target >= LATE_TARGET:
        var paired_growth: Dictionary = PairedDrift.compare(
            first_paired_window, previous_paired_window)
        if not paired_growth.get("accepted", false):
            _finish("late paired drift rejected " + JSON.stringify(paired_growth), false)
            return
        print("P2_PERF_E_PAIRED_LATE ", JSON.stringify(paired_growth))
    if target >= LATE_TARGET:
        var resource_growth: Dictionary = ResourceProbe.compare(
            first_resource_window, previous_resource_window)
        if not resource_growth.get("accepted", false):
            _finish("late resource growth rejected " + JSON.stringify(resource_growth), false)
            return
        print("P2_PERF_E_RESOURCE_LATE ", JSON.stringify(resource_growth))
    if target >= LATE_TARGET:
        var late_phase_growth: Dictionary = PhaseGrowth.compare(
            first_phase_window, previous_phase_window)
        if not late_phase_growth.get("accepted", false):
            _finish("late phase growth rejected " + JSON.stringify(late_phase_growth), false)
            return
        print("P2_PERF_E_PHASE_LATE_GROWTH ", JSON.stringify(late_phase_growth))
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
