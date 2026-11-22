extends RefCounted
## PERF E: non-negative authoritative sizes, signed deltas allowed.
const Metrics = preload("res://scripts/sim/phase2/n158_worker_request_metrics.gd")

static func run() -> Dictionary:
    var earlier: Dictionary = {"paid_tick": 100, "receipts": 12, "contracts": 5, "dock": 4, "events": 9, "ships": 24}
    var later: Dictionary = {"paid_tick": 300, "receipts": 13, "contracts": 2, "dock": 0, "events": 7, "ships": 24}
    var valid: Dictionary = Metrics.count_delta(earlier, later)
    if valid.get("contracts", 0) != -3 or valid.get("dock", 0) != -4 or valid.get("receipts", 0) != 1:
        return {"ok": false, "reason": "legitimate_cleanup_delta_lost"}
    var bad_before: Dictionary = earlier.duplicate(true)
    bad_before["contracts"] = -1
    if not Metrics.count_delta(bad_before, later).is_empty():
        return {"ok": false, "reason": "negative_initial_count_accepted"}
    var bad_after: Dictionary = later.duplicate(true)
    bad_after["events"] = -1
    if not Metrics.count_delta(earlier, bad_after).is_empty():
        return {"ok": false, "reason": "negative_final_count_accepted"}
    return {"ok": true}
