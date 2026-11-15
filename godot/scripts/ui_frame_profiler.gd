extends RefCounted
## UI-only frame recorder. Never accesses World, SceneTree or simulation state.
## The process timer excludes rendering; real FPS/frame delta reveal stalls
## outside _process. advance_frame contains simulation+signal callbacks.
const WINDOW_SIZE: int = 120
const DISPLAY_INTERVAL: float = 0.5

var _process_us: Array[int] = []
var _advance_us: Array[int] = []
var _ui_us: Array[int] = []
var _delta_us: Array[int] = []
var _ticks_window: Array[int] = []
var _frames: int = 0
var _ticks: int = 0
var _elapsed: float = 0.0
var _worst_frame_us: int = 0
var _worst_process_us: int = 0
var _worst_advance_us: int = 0
var _worst_ui_us: int = 0
var _last_frame_ticks: int = 0

func capture(frame_delta: float, process_usec: int, advance_usec: int,
        ui_usec: int, completed_ticks: int) -> void:
    _frames += 1
    _ticks += maxi(completed_ticks, 0)
    _last_frame_ticks = maxi(completed_ticks, 0)
    _elapsed += clampf(frame_delta, 0.0, 2.0)
    var full_frame_us: int = maxi(0, roundi(frame_delta * 1000000.0))
    _worst_frame_us = maxi(_worst_frame_us, full_frame_us)
    _worst_process_us = maxi(_worst_process_us, process_usec)
    _worst_advance_us = maxi(_worst_advance_us, advance_usec)
    _worst_ui_us = maxi(_worst_ui_us, ui_usec)
    _push(_process_us, process_usec)
    _push(_advance_us, advance_usec)
    _push(_ui_us, ui_usec)
    _push(_delta_us, full_frame_us)
    _push(_ticks_window, maxi(completed_ticks, 0))

func _push(samples: Array[int], usec: int) -> void:
    samples.append(maxi(0, usec))
    if samples.size() > WINDOW_SIZE:
        samples.pop_front()

func display_due() -> bool:
    if _elapsed < DISPLAY_INTERVAL:
        return false
    _elapsed = fmod(_elapsed, DISPLAY_INTERVAL)
    return true

func _average(values: Array[int]) -> float:
    if values.is_empty():
        return 0.0
    var total: int = 0
    for item in values:
        total += item
    return float(total) / float(values.size()) / 1000.0

func _p95(values: Array[int]) -> float:
    if values.is_empty():
        return 0.0
    var sorted: Array[int] = values.duplicate()
    sorted.sort()
    var idx: int = clampi(ceili(float(sorted.size()) * 0.95) - 1,
        0, sorted.size() - 1)
    return float(sorted[idx]) / 1000.0

func _max_window(values: Array[int]) -> float:
    var biggest: int = 0
    for value in values:
        biggest = maxi(biggest, value)
    return float(biggest) / 1000.0

func _tick_average() -> float:
    if _ticks_window.is_empty():
        return 0.0
    var total: int = 0
    for value in _ticks_window:
        total += value
    return float(total) / float(_ticks_window.size())

func _over_budget(values: Array[int]) -> int:
    var missed: int = 0
    for item in values:
        if item > 16667:  # 60 FPS 16.667ms CPU/main-thread budget
            missed += 1
    return missed

func summary() -> Dictionary:
    var process_mean: float = _average(_process_us)
    var advance_mean: float = _average(_advance_us)
    var ui_mean: float = _average(_ui_us)
    return {
        "fps": Engine.get_frames_per_second(),
        "frames": _frames, "ticks": _ticks,
        "last_frame_ticks": _last_frame_ticks,
        "ticks_per_frame_window": _tick_average(),
        "frame_p95_ms": _p95(_delta_us),
        "frame_window_max_ms": _max_window(_delta_us),
        "process_avg_ms": process_mean,
        "process_p95_ms": _p95(_process_us),
        "advance_avg_ms": advance_mean,
        "advance_p95_ms": _p95(_advance_us),
        "ui_avg_ms": ui_mean,
        "ui_p95_ms": _p95(_ui_us),
        "advance_share_of_process_pct": 100.0 * advance_mean /
            maxf(0.001, process_mean),
        "ui_share_of_process_pct": 100.0 * ui_mean /
            maxf(0.001, process_mean),
        "frame_over_16_7ms_window": _over_budget(_delta_us),
        "advance_over_16_7ms_window": _over_budget(_advance_us),
        "ui_over_16_7ms_window": _over_budget(_ui_us),
        "worst_frame_ms": float(_worst_frame_us) / 1000.0,
        "worst_process_ms": float(_worst_process_us) / 1000.0,
        "worst_advance_ms": float(_worst_advance_us) / 1000.0,
        "worst_ui_ms": float(_worst_ui_us) / 1000.0
    }

func compact_text() -> String:
    var data: Dictionary = summary()
    return "FPS %d · кадр p95 %.1f мс · sim+signals %.1f · UI %.1f · тик +%d" % [
        int(data["fps"]), float(data["frame_p95_ms"]),
        float(data["advance_p95_ms"]), float(data["ui_p95_ms"]),
        int(data["last_frame_ticks"])]
