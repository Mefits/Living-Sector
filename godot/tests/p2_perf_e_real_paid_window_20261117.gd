extends RefCounted
## E negative regression: only exact consecutive single-paid-tick worker
## request wall measurements may certify a checkpoint window.
const Metrics = preload("res://scripts/sim/phase2/n158_worker_request_metrics.gd")

static func run() -> Dictionary:
    var rows: Array = []
    for tick in range(1, 101):
        var row: Dictionary = Metrics.summarize(tick - 1, tick, 100, 200, 225)
        row["after_tick"] = tick
        rows.append(row)
    var complete: Dictionary = Metrics.bounded_paid_tick_window(rows, 100)
    if not complete.get("complete", false) or complete.get("observed_paid_ticks", -1) != 100:
        return {"ok": false, "reason": "complete_window_rejected"}
    if complete.get("advance_wall_avg_usec", -1.0) != 100.0 or complete.get("projection_wall_avg_usec", -1.0) != 25.0:
        return {"ok": false, "reason": "wrong_attribution"}
    var missing: Array = rows.duplicate(true)
    missing.remove_at(45)
    if Metrics.bounded_paid_tick_window(missing, 100).get("complete", true):
        return {"ok": false, "reason": "missing_tick_accepted"}
    var multi: Array = rows.duplicate(true)
    multi[50]["paid_ticks"] = 2
    if not Metrics.bounded_paid_tick_window(multi, 100).is_empty():
        return {"ok": false, "reason": "multi_tick_request_accepted"}
    var malformed: Array = rows.duplicate(true)
    malformed[10]["request_wall_usec"] = 1
    if not Metrics.bounded_paid_tick_window(malformed, 100).is_empty():
        return {"ok": false, "reason": "invalid_projection_attribution_accepted"}
    return {"ok": true}
