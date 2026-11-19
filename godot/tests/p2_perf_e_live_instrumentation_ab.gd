extends SceneTree
## E: real opt-in profiler-on/off N158 same-seed A/B. Both arms execute
## independent paid ticks; checkpoint and comparison occur OUTSIDE step timing.
## Run: godot --headless --path godot -s res://tests/p2_perf_e_live_instrumentation_ab.gd
## LS_E_AB_EXTENDED=1 opts into 900 ticks; no Actions/CI invocation here.
const NativeData = preload("res://scripts/native_data.gd")
const Plain = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Profiled = preload("res://scripts/sim/phase2/n158_timed_phase_probe.gd")
const AB = preload("res://scripts/sim/phase2/n158_instrumentation_ab_acceptance.gd")
const Oracle = preload("res://scripts/sim/phase2/n158_checkpoint_parity_oracle.gd")
const MAX_WALL_MS: int = 480000
const CHECKPOINT_STRIDE: int = 10
const CHECKPOINTS: Array[int] = [100, 300, 600, 900]
var _plain = null
var _profiled = null
var _start_ms: int = 0
var _failed: String = ""
var _steps_plain: int = 0
var _steps_profiled: int = 0

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    _start_ms = Time.get_ticks_msec()
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _finish(false, "seed unavailable")
        return
    _plain = Plain.new()
    _profiled = Profiled.new()
    if not _plain.start_from_seed(seed.duplicate(true)) or not (
            _profiled.start_from_seed(seed.duplicate(true))):
        _finish(false, "independent seed boot failed")
        return
    for runner in [_plain, _profiled]:
        if not runner.queue_control("pause"):
            _finish(false, "pause rejected")
            return
        runner.advance_frame(0.0)
        if runner.tick_count != 0 or not runner.last_phase_failure().is_empty():
            _finish(false, "initial source clock invalid")
            return
    var target: int = 900 if OS.get_environment("LS_E_AB_EXTENDED") == "1" else 300
    var previous: Dictionary = {}
    var reports: Array = []
    for end_tick in CHECKPOINTS:
        if end_tick > target:
            break
        var first_tick: int = end_tick - 99
        # Advance BOTH real simulations through the gap, including source
        # economy/AI/cadence. No synthetic state jump or skipped paid ticks.
        while _plain.tick_count < first_tick - 1:
            if not _within_budget():
                _finish(false, "wall budget before warmup")
                return
            var next_tick: int = _plain.tick_count + 1
            var warm_plain: Dictionary = _plain_step(next_tick)
            var warm_profiled: Dictionary = _profile_step(next_tick)
            if not warm_plain.get("ok", false) or not warm_profiled.get("ok", false):
                _finish(false, "warmup paid tick failed " + str(next_tick))
                return
        if not _within_budget():
            _finish(false, "wall budget before A/B window")
            return
        var result: Dictionary = AB.run_pair(first_tick, 100,
            Callable(self, "_plain_step"), Callable(self, "_profile_step"),
            Callable(self, "_exact"), CHECKPOINT_STRIDE)
        if not result.get("accepted", false):
            _finish(false, "A/B rejected " + JSON.stringify(result))
            return
        if _plain.tick_count != end_tick or _profiled.tick_count != end_tick:
            _finish(false, "checkpoint clock mismatch " + str(end_tick))
            return
        # This is a second independent full-state oracle at window boundary.
        var exact: Dictionary = Oracle.compare(_plain.checkpoint(), _profiled.checkpoint())
        if not exact.get("equal", false):
            _finish(false, "boundary divergence " + JSON.stringify(exact))
            return
        # Profiler must have observed the actual paid phase calls; this
        # excludes an accidentally uninstrumented profiled runtime.
        var observed: Dictionary = _profiled.paid_phase_totals(end_tick)
        if observed.is_empty() or int(observed.get("observed_paid_ticks", 0)) != 100:
            _finish(false, "missing real profiled phase window " + str(end_tick))
            return
        if not previous.is_empty():
            var drift: Dictionary = AB.compare_windows(previous, result)
            if not drift.get("accepted", false):
                _finish(false, "A/B drift rejected " + JSON.stringify(drift))
                return
            print("P2_PERF_E_LIVE_AB_DRIFT ", JSON.stringify(drift))
        previous = result.duplicate(true)
        reports.append(result.duplicate(true))
        print("P2_PERF_E_LIVE_AB_WINDOW ", JSON.stringify(result))
    if reports.is_empty() or _steps_plain != target or _steps_profiled != target:
        _finish(false, "incomplete paid tick coverage")
        return
    print("P2_PERF_E_LIVE_AB_PASS target=", target,
        " parity_stride=", CHECKPOINT_STRIDE,
        " profiler_cost_is_not_cpu=true")
    quit(0)

func _plain_step(tick: int) -> Dictionary:
    return _step(_plain, tick, false)

func _profile_step(tick: int) -> Dictionary:
    return _step(_profiled, tick, true)

func _step(runner, tick: int, instrumented: bool) -> Dictionary:
    if not _within_budget() or runner.tick_count != tick - 1:
        return {"ok": false, "tick": tick, "reason": "budget_or_source_clock"}
    if not runner.queue_control("step", 1):
        return {"ok": false, "tick": tick, "reason": "step_refused"}
    var began: int = Time.get_ticks_usec()
    runner.advance_frame(0.0)
    var elapsed: int = maxi(0, Time.get_ticks_usec() - began)
    if runner.tick_count != tick or not runner.last_phase_failure().is_empty():
        return {"ok": false, "tick": tick, "reason": "paid_tick_failed"}
    if instrumented:
        _steps_profiled += 1
    else:
        _steps_plain += 1
    # No separate measured instrumentation cost is available from the
    # source probe; 0 means unknown/not isolated, NOT zero overhead.
    # Checkpoint cost is intentionally excluded from elapsed_usec.
    var sample: Dictionary = {"ok": true, "tick": tick,
        "elapsed_usec": elapsed, "instrumentation_usec": 0}
    # Full checkpoint is outside timing and only on a periodic parity gate.
    # Intermediate ticks remain real paid ticks with exact SourceClock checks.
    if tick % CHECKPOINT_STRIDE == 0:
        sample["checkpoint"] = runner.checkpoint()
    return sample

func _exact(a: Dictionary, b: Dictionary) -> bool:
    return Oracle.compare(a, b).get("equal", false) == true

func _within_budget() -> bool:
    return Time.get_ticks_msec() - _start_ms < MAX_WALL_MS

func _finish(ok: bool, why: String) -> void:
    if not ok:
        push_error("P2_PERF_E_LIVE_AB_FAIL " + why)
    quit(0 if ok else 1)
