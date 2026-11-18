extends SceneTree
## Headless contract check for visual speed selector and original perf core.
const Lab = preload("res://scripts/main.gd")
const Profiler = preload("res://scripts/ui_frame_profiler.gd")

func _initialize() -> void:
    var ui = Lab.new()
    var okay: bool = ui.speed == 1 and ui.native_time == 0.0
    for candidate in [1, 4, 8, 16]:
        ui.native_time = 0.0
        ui._set_speed(candidate)
        ui._advance_visual_clock(0.5)
        okay = okay and ui.speed == candidate
        okay = okay and is_equal_approx(ui.native_time, 10.0 * candidate)
    ui.native_time = 100.0
    ui.paused = true
    ui._advance_visual_clock(1.0)
    okay = okay and is_equal_approx(ui.native_time, 100.0)
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
