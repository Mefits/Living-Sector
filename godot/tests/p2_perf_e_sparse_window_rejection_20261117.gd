extends SceneTree
## PERF E: 100-slot bounded paid-tick attribution; gaps cannot masquerade as samples.
const Metrics = preload("res://scripts/sim/phase2/n158_worker_request_metrics.gd")

func _initialize() -> void:
    var samples: Array = []
    for tick in range(1, 101):
        var row: Dictionary = Metrics.summarize(tick - 1, tick, 1000, 1100, 1120)
        row["after_tick"] = tick
        samples.append(row)
    var full: Dictionary = Metrics.bounded_paid_tick_window(samples, 100)
    if not _check(full.get("complete", false) == true, "full window"):
        return
    var prefix: Dictionary = Metrics.bounded_paid_tick_window(samples.slice(0, 99), 100)
    if not _check(prefix.get("complete", true) == false and prefix.get("observed_paid_ticks", 0) == 99, "contiguous prefix"):
        return
    var gap: Array = samples.duplicate(true)
    gap.remove_at(40)
    if not _check(Metrics.bounded_paid_tick_window(gap, 100).is_empty(), "internal gap"):
        return
    var wrong_start: Array = samples.slice(1, 100)
    if not _check(Metrics.bounded_paid_tick_window(wrong_start, 100).is_empty(), "missing first tick"):
        return
    var oversized: Array = samples.duplicate(true)
    oversized.append(samples[99].duplicate(true))
    if not _check(Metrics.bounded_paid_tick_window(oversized, 100).is_empty(), "over 100 samples"):
        return
    print("P2_PERF_E_SPARSE_WINDOW_REJECTION_PASS")
    quit(0)

func _check(ok: bool, reason: String) -> bool:
    if not ok:
        push_error("P2_PERF_E_SPARSE_WINDOW_REJECTION_FAIL " + reason)
        quit(1)
        return false
    return true
