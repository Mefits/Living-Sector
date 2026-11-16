extends SceneTree
## PR #262 current-HEAD acceptance, not a new benchmark or replacement for
## 2600-tick exact replay. Exactly 500 REAL paid N158 ticks; hard wall budget.
## A budget exhaustion is a failure, never a false green partial smoke.
const NativeData = preload("res://scripts/native_data.gd")
const SourceN158 = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const TARGET_TICK: int = 500
const MAX_WALL_MSEC: int = 300000
const SAMPLE_WINDOW: int = 100

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("source seed missing: " + str(seed["error"]))
        return
    var sim = SourceN158.new()
    if not sim.start_from_seed(seed):
        _fail("source refused seed: " + sim.boot_error())
        return
    if not sim.queue_control("pause") or not sim.queue_control("speed", 16.0):
        _fail("cannot establish source clock controls")
        return
    sim.advance_frame(0.0)
    if sim.tick_count != 0:
        _fail("unexpected boot tick " + str(sim.tick_count))
        return

    var started_msec: int = Time.get_ticks_msec()
    var samples: Array[int] = []
    for expected_tick in range(1, TARGET_TICK + 1):
        if Time.get_ticks_msec() - started_msec > MAX_WALL_MSEC:
            _fail("wall budget exhausted at tick " + str(sim.tick_count)
                + " before required tick " + str(TARGET_TICK))
            return
        if not sim.queue_control("step", 1):
            _fail("real paid step refused at tick " + str(expected_tick))
            return
        var began_usec: int = Time.get_ticks_usec()
        sim.advance_frame(0.0)
        var cost_usec: int = maxi(0, Time.get_ticks_usec() - began_usec)
        if sim.tick_count != expected_tick:
            _fail("tick advancement divergence: expected=" + str(expected_tick)
                + " got=" + str(sim.tick_count))
            return
        var phase_error: Dictionary = sim.last_phase_failure()
        if not phase_error.is_empty():
            _fail("native phase failure at " + str(expected_tick)
                + ": " + JSON.stringify(phase_error))
            return
        samples.append(cost_usec)
        if samples.size() > SAMPLE_WINDOW:
            samples.pop_front()
        if expected_tick in [100, 300, 500]:
            var sorted: Array[int] = samples.duplicate()
            sorted.sort()
            var total_usec: int = 0
            for value in samples:
                total_usec += value
            var p95_index: int = clampi(ceili(float(sorted.size()) * 0.95) - 1,
                0, sorted.size() - 1)
            print("P2_PR262_HEAD_500_TICK_WINDOW ", JSON.stringify({
                "tick": expected_tick, "paid_ticks": sorted.size(),
                "avg_ms": snappedf(float(total_usec) /
                    float(sorted.size()) / 1000.0, 0.01),
                "p95_ms": snappedf(float(sorted[p95_index]) / 1000.0, 0.01),
                "elapsed_s": snappedf(float(Time.get_ticks_msec() -
                    started_msec) / 1000.0, 0.01)
            }))
    # One committed read-only presentation projection, as the worker does.
    var economy: Dictionary = sim.economy_snapshot()
    if economy.is_empty():
        _fail("500 real ticks completed but final economy is unavailable")
        return
    var ships: Variant = economy.get("ships", {})
    if not (ships is Dictionary) or ships.is_empty():
        _fail("500 real ticks completed but ship economy is missing")
        return
    print("P2_PR262_HEAD_500_TICK_PASS ", JSON.stringify({
        "tick": sim.tick_count, "ships": ships.size(),
        "elapsed_s": snappedf(float(Time.get_ticks_msec() -
            started_msec) / 1000.0, 0.01),
        "source_phases_ok": true, "seed": "native_current_world"
    }))
    quit(0)

func _fail(message: String) -> void:
    push_error("P2_PR262_HEAD_500_TICK_FAIL " + message)
    quit(1)
