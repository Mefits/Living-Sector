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
const PhaseAcceptance = preload("res://scripts/sim/phase2/n158_live_ab_phase_acceptance.gd")
const Structure = preload("res://scripts/sim/phase2/n158_checkpoint_structure_growth.gd")
const MAX_WALL_MS: int = 480000
const CHECKPOINT_STRIDE: int = 10
const CHECKPOINTS: Array[int] = [100, 300, 600, 900]
var _plain = null
var _profiled = null
var _start_ms: int = 0
var _failed: String = ""
var _steps_plain: int = 0
var _steps_profiled: int = 0
var _active_stride: int = CHECKPOINT_STRIDE
var _warmup_plain: int = 0
var _warmup_profiled: int = 0
var _warmup_checkpoint_count: int = 0

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    _start_ms = Time.get_ticks_msec()
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _finish(false, "seed unavailable")
        return
    var mode_reports: Array = []
    for stride in [1, CHECKPOINT_STRIDE]:
        _active_stride = stride
        _steps_plain = 0
        _steps_profiled = 0
        _warmup_plain = 0
        _warmup_profiled = 0
        _warmup_checkpoint_count = 0
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
        var previous_structure: Dictionary = {}
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
                var warm_plain: Dictionary = _step(_plain, next_tick, false, false)
                var warm_profiled: Dictionary = _step(_profiled, next_tick, true, false)
                if not warm_plain.get("ok", false) or not warm_profiled.get("ok", false) or (
                        warm_plain.has("checkpoint") or warm_profiled.has("checkpoint") or
                        warm_plain.has("checkpoint_usec") or warm_profiled.has("checkpoint_usec")):
                    _finish(false, "warmup paid tick failed " + str(next_tick))
                    return
            if not _within_budget():
                _finish(false, "wall budget before A/B window")
                return
            # One detached boundary oracle after warmup, never a full copy
            # after each warmup tick. Keep it outside the paid-time samples.
            if first_tick > 1:
                var warm_boundary: Dictionary = Oracle.compare(
                    _plain.checkpoint(), _profiled.checkpoint())
                if not warm_boundary.get("equal", false):
                    _finish(false, "warmup boundary divergence " + str(first_tick))
                    return
            var result: Dictionary = AB.run_pair(first_tick, 100,
                Callable(self, "_plain_step"), Callable(self, "_profile_step"),
                Callable(self, "_exact"), _active_stride)
            if not result.get("accepted", false):
                _finish(false, "A/B rejected " + JSON.stringify(result))
                return
            if _plain.tick_count != end_tick or _profiled.tick_count != end_tick:
                _finish(false, "checkpoint clock mismatch " + str(end_tick))
                return
            # This is a second independent full-state oracle at window boundary.
            var plain_checkpoint: Dictionary = _plain.checkpoint()
            var profiled_checkpoint: Dictionary = _profiled.checkpoint()
            var exact: Dictionary = Oracle.compare(plain_checkpoint, profiled_checkpoint)
            if not exact.get("equal", false):
                _finish(false, "boundary divergence " + JSON.stringify(exact))
                return
            # Reuse the already detached parity checkpoint: no extra World copy.
            # Structural counting is outside paid-tick timing and never retained.
            var structure: Dictionary = Structure.pair(
                Structure.capture(end_tick, plain_checkpoint),
                Structure.capture(end_tick, profiled_checkpoint), exact)
            plain_checkpoint.clear()
            profiled_checkpoint.clear()
            if not structure.get("accepted", false):
                _finish(false, "checkpoint structure rejected " + JSON.stringify(structure))
                return
            print("P2_PERF_E_CHECKPOINT_STRUCTURE ", JSON.stringify(structure))
            if not previous_structure.is_empty():
                var structure_growth: Dictionary = Structure.growth(previous_structure, structure)
                if not structure_growth.get("accepted", false):
                    _finish(false, "checkpoint structure growth rejected")
                    return
                print("P2_PERF_E_CHECKPOINT_STRUCTURE_GROWTH ", JSON.stringify(structure_growth))
            previous_structure = structure
            # Profiler must have observed the actual paid phase calls; this
            # excludes an accidentally uninstrumented profiled runtime.
            var observed: Dictionary = _profiled.paid_phase_totals(end_tick)
            if observed.is_empty() or int(observed.get("observed_paid_ticks", 0)) != 100:
                _finish(false, "missing real profiled phase window " + str(end_tick))
                return
            var distribution: Dictionary = _profiled.paid_phase_distribution(end_tick)
            var sites: Dictionary = _profiled.paid_callsite_costs(end_tick)
            var phase_evidence: Dictionary = PhaseAcceptance.accept(
                result, distribution, sites, end_tick)
            if not phase_evidence.get("accepted", false):
                _finish(false, "live phase/callsite accounting rejected " + JSON.stringify(phase_evidence))
                return
            print("P2_PERF_E_LIVE_AB_PHASE_CALLS ", JSON.stringify(phase_evidence))
            if not previous.is_empty():
                var drift: Dictionary = AB.compare_windows(previous, result)
                if not drift.get("accepted", false):
                    _finish(false, "A/B drift rejected " + JSON.stringify(drift))
                    return
                print("P2_PERF_E_LIVE_AB_DRIFT ", JSON.stringify(drift))
            previous = result.duplicate(true)
            reports.append(result.duplicate(true))
            print("P2_PERF_E_LIVE_AB_WINDOW ", JSON.stringify(result))
        if reports.is_empty() or _steps_plain != target or _steps_profiled != target or (
                _warmup_plain != target - reports.size() * 100 or
                _warmup_profiled != _warmup_plain or _warmup_checkpoint_count != 0):
            _finish(false, "incomplete paid tick coverage")
            return
        mode_reports.append(reports.duplicate(true))
    var comparison: Dictionary = AB.compare_checkpoint_modes(mode_reports[0], mode_reports[1])
    if not comparison.get("accepted", false):
        _finish(false, "independent mode comparison rejected " + JSON.stringify(comparison))
        return
    print("P2_PERF_E_CHECKPOINT_MODE_COMPARISON ", JSON.stringify(comparison))
    print("P2_PERF_E_LIVE_AB_PASS target=", target,
        " independent_modes=2 profiler_cost_is_not_cpu=true")
    quit(0)

func _plain_step(tick: int) -> Dictionary:
    return _step(_plain, tick, false, true)

func _profile_step(tick: int) -> Dictionary:
    return _step(_profiled, tick, true, true)

func _step(runner, tick: int, instrumented: bool,
        capture_checkpoint: bool) -> Dictionary:
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
        if not capture_checkpoint:
            _warmup_profiled += 1
    else:
        _steps_plain += 1
        if not capture_checkpoint:
            _warmup_plain += 1
    # No separate measured instrumentation cost is available from the
    # source probe; 0 means unknown/not isolated, NOT zero overhead.
    # Checkpoint cost is intentionally excluded from elapsed_usec.
    var sample: Dictionary = {"ok": true, "tick": tick,
        "elapsed_usec": elapsed, "instrumentation_usec": 0}
    # Full checkpoint is outside timing and only on a periodic parity gate.
    # Intermediate ticks remain real paid ticks with exact SourceClock checks.
    if capture_checkpoint and tick % _active_stride == 0:
        var checkpoint_began: int = Time.get_ticks_usec()
        sample["checkpoint"] = runner.checkpoint()
        sample["checkpoint_usec"] = maxi(0, Time.get_ticks_usec() - checkpoint_began)
    return sample

func _exact(a: Dictionary, b: Dictionary) -> bool:
    return Oracle.compare(a, b).get("equal", false) == true

func _within_budget() -> bool:
    return Time.get_ticks_msec() - _start_ms < MAX_WALL_MS

func _finish(ok: bool, why: String) -> void:
    if not ok:
        push_error("P2_PERF_E_LIVE_AB_FAIL " + why)
    quit(0 if ok else 1)
