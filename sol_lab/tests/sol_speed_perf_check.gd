extends SceneTree
## Compare Sol Lab visual clock with SystemBalance's unchanged native clock.
const Lab = preload("res://scripts/main.gd")
const Clock = preload("res://scripts/sim/clock.gd")
const Profiler = preload("res://scripts/ui_frame_profiler.gd")

func _initialize() -> void:
    var ui = Lab.new()
    var reference = Clock.new()
    var okay: bool = ui.speed == 1 and ui.native_time == 0.0
    okay = okay and reference.ticks_per_second == 8
    for candidate in [1, 4, 8, 16]:
        ui.native_time = 0.0
        ui.visual_tick_count = 0
        ui._set_speed(candidate)
        reference.reset()
        reference.set_speed(float(candidate))
        var expected: float = 0.0
        var expected_ticks: int = 0
        # Eight 125ms frames equal exactly one second at the native 8 TPS.
        for frame in range(8):
            var native_steps: int = reference.consume_frame(0.125)
            expected_ticks += native_steps
            expected += float(native_steps) * reference.tick_scale()
            ui._advance_visual_clock(0.125)
        okay = okay and ui.speed == candidate
        okay = okay and ui.visual_tick_count == expected_ticks
        okay = okay and expected_ticks == 8
        okay = okay and is_equal_approx(ui.native_time, expected)
        okay = okay and is_equal_approx(ui.native_time, float(candidate))
        # At one original tick the delta is speed/8, not a full unit.
        ui.paused = true
        ui.visual_clock.set_paused(true)
        var prior_time: float = ui.native_time
        ui._advance_visual_clock(1.0)
        okay = okay and is_equal_approx(ui.native_time, prior_time)
        ui._step()
        okay = okay and is_equal_approx(ui.native_time,
            prior_time + float(candidate) / 8.0)
        ui.paused = false
        ui.visual_clock.set_paused(false)
    ui._set_speed(3)
    okay = okay and ui.speed == 16
    var sample = Profiler.new()
    sample.capture(0.016, 1500, 0, 850, 0)
    var summary: Dictionary = sample.summary()
    okay = okay and int(summary["ticks"]) == 0
    okay = okay and float(summary["ui_p95_ms"]) > 0.0
    okay = okay and float(summary["advance_p95_ms"]) == 0.0
    ui.free()
    if okay:
        print("SOL_SPEED_PERF_PASS")
        quit(0)
    else:
        push_error("SOL_SPEED_PERF_FAIL")
        quit(1)
