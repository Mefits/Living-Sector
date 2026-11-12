extends SceneTree
## Godot --headless --path godot --script res://tests/n2_calendar_check.gd
const Runner = preload("res://scripts/sim/tick_runner.gd")
const NativeData = preload("res://scripts/native_data.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("seed")
        return
    var a = Runner.new()
    var b = Runner.new()
    if not a.start_from_seed(seed) or not b.start_from_seed(seed):
        _fail("start")
        return
    # Different frame grouping, same number of committed ticks.
    a.queue_control("pause")
    a.queue_control("step", 8)
    a.advance_frame(0.0)
    b.queue_control("pause")
    for i in range(8):
        b.queue_control("step", 1)
        b.advance_frame(0.0)
    if a.tick_count != 8 or b.tick_count != 8:
        _fail("tick count")
        return
    if absf(a.calendar.native_time_units - 0.25) > 0.000001:
        _fail("native units: 8 * 0.25 / 8")
        return
    if a.calendar.snapshot() != b.calendar.snapshot():
        _fail("frame partition changed calendar")
        return
    var snapshot: Dictionary = a.checkpoint()
    var resumed = Runner.new()
    resumed.start_from_seed(seed)
    if not resumed.restore_checkpoint(snapshot, seed):
        _fail("calendar restore")
        return
    if resumed.calendar.snapshot() != a.calendar.snapshot():
        _fail("calendar checkpoint mismatch")
        return
    var broken: Dictionary = snapshot.duplicate(true)
    broken["calendar"]["native_time_units"] = -1.0
    if resumed.restore_checkpoint(broken, seed):
        _fail("negative elapsed accepted")
        return
    if resumed.calendar.snapshot() != a.calendar.snapshot():
        _fail("invalid restore mutated live state")
        return
    var legacy: Dictionary = snapshot.duplicate(true)
    legacy.erase("calendar")
    if not resumed.restore_checkpoint(legacy, seed):
        _fail("schema v1 backward compatibility")
        return
    if resumed.calendar.origin_known:
        _fail("legacy elapsed was fabricated")
        return
    if not resumed.calendar.set_hours_per_native_unit(24.0):
        _fail("explicit conversion")
        return
    if resumed.calendar.set_hours_per_native_unit(-1.0):
        _fail("invalid conversion accepted")
        return
    print("N2_CALENDAR_PASS: FPS partition, native units, save/load, legacy unknown epoch, invalid restore")
    quit(0)

func _fail(message: String) -> void:
    push_error("N2_CALENDAR_FAIL: " + message)
    quit(1)
