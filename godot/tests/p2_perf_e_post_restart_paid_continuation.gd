extends SceneTree
const PROBE = preload("res://scripts/sim/phase2/n158_post_restart_paid_continuation.gd")

func _initialize() -> void:
    var rows: Array = []
    for tick in range(301, 304):
        var source: Dictionary = {"tick": tick, "native_production": {
            "ledger": {"receipts": [{"id": tick}]}, "rng": [tick, 2],
            "world": {"ships": {"s": {"cargo": tick}}}}, "events": {"pending": []}}
        var step: Dictionary = {"ok": true, "advanced": true, "tick": tick,
            "timing": {"advance_wall_usec": 12, "projection_wall_usec": 3,
                "request_wall_usec": 20}}
        var checkpoint: Dictionary = {"ok": true, "tick": tick,
            "checkpoint": source.duplicate(true)}
        var row: Dictionary = PROBE.accept_step(tick - 1, tick, source, step,
            checkpoint, 15, 22)
        if not row.get("accepted", false):
            _fail("valid step " + str(row))
            return
        rows.append(row)
        var changed: Dictionary = checkpoint.duplicate(true)
        changed["checkpoint"]["native_production"]["world"]["ships"]["s"]["cargo"] += 1
        if PROBE.accept_step(tick - 1, tick, source, step, changed, 15, 22).get("accepted", false):
            _fail("cargo divergence accepted")
            return
        changed = checkpoint.duplicate(true)
        changed["checkpoint"]["native_production"]["rng"][0] += 1
        if PROBE.accept_step(tick - 1, tick, source, step, changed, 15, 22).get("accepted", false):
            _fail("rng divergence accepted")
            return
        changed = checkpoint.duplicate(true)
        changed["checkpoint"]["native_production"]["ledger"]["receipts"].clear()
        if PROBE.accept_step(tick - 1, tick, source, step, changed, 15, 22).get("accepted", false):
            _fail("ledger divergence accepted")
            return
        var bad_step: Dictionary = step.duplicate(true)
        bad_step["tick"] = tick + 1
        if PROBE.accept_step(tick - 1, tick, source, bad_step, checkpoint, 15, 22).get("accepted", false):
            _fail("skipped paid tick accepted")
            return
        bad_step = step.duplicate(true)
        bad_step["timing"]["request_wall_usec"] = 1
        if PROBE.accept_step(tick - 1, tick, source, bad_step, checkpoint, 15, 22).get("accepted", false):
            _fail("invalid worker timing accepted")
            return
    var report: Dictionary = PROBE.summarize(300, rows)
    if not report.get("accepted", false) or report.get("last_paid_tick") != 303 or (
            report.get("direct_total_wall_usec") != 45 or
            report.get("worker_request_total_wall_usec") != 66):
        _fail("valid report rejected " + str(report))
        return
    var forged: Array = rows.duplicate(true)
    forged[1]["tick"] = 305
    if PROBE.summarize(300, forged).get("accepted", false):
        _fail("source gap accepted")
        return
    forged = rows.duplicate(true)
    forged[1]["exact"] = false
    if PROBE.summarize(300, forged).get("accepted", false):
        _fail("non-exact parity accepted")
        return
    forged = rows.duplicate(true)
    forged[0]["worker_request_wall_usec"] = 1
    if PROBE.summarize(300, forged).get("accepted", false):
        _fail("request underflow accepted")
        return
    if PROBE.summarize(300, rows + rows).get("accepted", false):
        _fail("unbounded continuation accepted")
        return
    print("P2_PERF_E_POST_RESTART_PAID_CONTINUATION_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_POST_RESTART_PAID_CONTINUATION_FAIL " + reason)
    quit(1)
