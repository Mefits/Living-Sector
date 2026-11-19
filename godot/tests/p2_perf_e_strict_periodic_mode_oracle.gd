extends SceneTree
## Independent mode report oracle: positive matching windows and negative
## forged bounds/gates/accounting, incomplete runs and overlapping windows.
const AB = preload("res://scripts/sim/phase2/n158_instrumentation_ab_acceptance.gd")

func _initialize() -> void:
    var strict: Array = [_row(1, 100, 1), _row(201, 300, 1)]
    var periodic: Array = [_row(1, 100, 10), _row(201, 300, 10)]
    var good: Dictionary = AB.compare_checkpoint_modes(strict, periodic)
    if not good.get("accepted", false) or good.get("windows", []).size() != 2 or (
            good.get("paid_wall_difference_usec", -1) != 0):
        _fail("valid independent modes rejected " + str(good))
        return
    var bad: Array = [
        {"field": "from_tick", "value": 2},
        {"field": "checkpoint_stride", "value": 1},
        {"field": "parity_gates", "value": 9},
        {"field": "observed_delta_total_usec", "value": 99},
        {"field": "paid_ticks", "value": 99},
        {"field": "time_kind", "value": "cpu"},
        {"field": "accepted", "value": false}
    ]
    for mutation in bad:
        var altered: Array = periodic.duplicate(true)
        altered[0][mutation["field"]] = mutation["value"]
        if AB.compare_checkpoint_modes(strict, altered).get("accepted", false):
            _fail("forged mode accepted " + str(mutation))
            return
    if AB.compare_checkpoint_modes(strict, [periodic[0]]).get("accepted", false):
        _fail("incomplete independent mode accepted")
        return
    var overlap: Array = periodic.duplicate(true)
    overlap[1] = _row(50, 149, 10)
    if AB.compare_checkpoint_modes(strict, overlap).get("accepted", false):
        _fail("overlapping windows accepted")
        return
    var wrong_strict: Array = strict.duplicate(true)
    wrong_strict[0]["checkpoint_stride"] = 10
    wrong_strict[0]["parity_gates"] = 10
    if AB.compare_checkpoint_modes(wrong_strict, periodic).get("accepted", false):
        _fail("non-strict baseline accepted")
        return
    print("P2_PERF_E_STRICT_PERIODIC_MODE_ORACLE_PASS")
    quit(0)

func _row(first: int, last: int, stride: int) -> Dictionary:
    return {"accepted": true, "from_tick": first, "to_tick": last,
        "paid_ticks": last - first + 1, "checkpoint_stride": stride,
        "parity_gates": ceili(float(last - first + 1) / float(stride)),
        "plain_total_usec": 1000, "profiled_total_usec": 1200,
        "observed_delta_total_usec": 200,
        "measured_instrumentation_total_usec": 0,
        "checkpoint_plain_total_usec": 2 * ceili(float(last - first + 1) / float(stride)),
        "checkpoint_profiled_total_usec": 3 * ceili(float(last - first + 1) / float(stride)),
        "checkpoint_total_usec": 5 * ceili(float(last - first + 1) / float(stride)),
        "checkpoint_time_excluded": true,
        "order": "alternating", "time_kind": "elapsed_wall_not_cpu"}

func _fail(message: String) -> void:
    push_error("P2_PERF_E_STRICT_PERIODIC_MODE_ORACLE_FAIL " + message)
    quit(1)
