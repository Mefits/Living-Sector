extends SceneTree
## N55: short isolated Godot clock admission regression.
const Clock = preload("res://scripts/sim/clock.gd")

func _initialize() -> void:
    var c = Clock.new()
    var failures: Array[String] = []
    _check(c.tick_scale() == 0.03125, "native default scale", failures)
    _check(c.consume_frame(0.0625) == 0, "half interval", failures)
    _check(c.consume_frame(0.0625) == 1, "two halves", failures)
    _check(c.consume_frame(0.25) == 2, "normal frame cadence", failures)
    _check(c.consume_frame(12.0) == 1, "hitch must not burst", failures)
    _check(c.last_admission().get("mode") == "hitch", "hitch provenance", failures)
    _check(c.consume_frame(0.0) == 0, "hitch backlog discarded", failures)
    c.set_paused(true)
    _check(c.consume_frame(1.0) == 0, "paused no ticks", failures)
    _check(c.request_steps(40), "manual queue accepted", failures)
    _check(c.consume_frame(0.0) == 16, "manual bounded first chunk", failures)
    _check(c.consume_frame(0.0) == 16, "manual bounded second chunk", failures)
    _check(c.consume_frame(0.0) == 8, "manual remainder", failures)
    _check(c.consume_frame(0.0) == 0, "no replay", failures)
    _check(c.set_speed(16.0), "native speed control", failures)
    _check(is_equal_approx(c.tick_scale(), 2.0), "speed does not alter tps", failures)
    var saved: Dictionary = c.snapshot()
    var restored = Clock.new()
    _check(restored.restore(saved), "restore", failures)
    _check(restored.consume_frame(0.0) == 0, "no phantom ticks after restore", failures)
    _check(restored.paused and restored.world_speed == 16.0, "controls survive", failures)
    if failures.is_empty():
        print("N55_CLOCK_ADMISSION_PASS")
        quit(0)
    else:
        for failure in failures:
            push_error("N55 " + failure)
        quit(1)

func _check(condition: bool, message: String, failures: Array[String]) -> void:
    if not condition:
        failures.append(message)
