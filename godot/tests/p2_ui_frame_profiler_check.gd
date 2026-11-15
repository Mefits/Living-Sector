extends SceneTree
## UI-only deterministic unit proof; no N39 state, no TickRunner, no CI.
const Frame = preload("res://scripts/ui_frame_profiler.gd")

func _initialize() -> void:
    var profile = Frame.new()
    for i in range(120):
        profile.capture(0.016, 15000, 12000, 2000, 1)
    var info: Dictionary = profile.summary()
    if info["frames"] != 120 or info["ticks"] != 120 or not (
            is_equal_approx(float(info["process_p95_ms"]), 15.0)) or not (
            is_equal_approx(float(info["advance_avg_ms"]), 12.0)) or not (
            is_equal_approx(float(info["ui_avg_ms"]), 2.0)):
        _fail("120-frame bounded rolling CPU profile incorrect: " + str(info))
        return
    if not profile.display_due() or profile.display_due():
        _fail("UI rate limit did not cap report updates")
        return
    profile.capture(0.1, 90000, 82000, 5000, 4)
    info = profile.summary()
    if info["last_frame_ticks"] != 4 or info["ticks"] != 124 or (
            float(info["worst_frame_ms"]) < 99.9) or (
            float(info["worst_process_ms"]) < 89.9) or (
            float(info["process_p95_ms"]) < 14.9):
        _fail("real wall-frame stall lost or cumulative ticks drifted")
        return
    if profile.compact_text().is_empty():
        _fail("always-visible FPS label empty")
        return
    print("P2_UI_FRAME_PROFILER_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_UI_FRAME_PROFILER_FAIL: " + reason)
    quit(1)
