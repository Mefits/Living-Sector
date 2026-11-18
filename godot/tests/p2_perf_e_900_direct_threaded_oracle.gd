extends SceneTree
## E: bounded 600/900 detached checkpoints and independent 100-tick windows.
## No source ticks fabricated: fixtures test acceptance only; live runner does real ticks.
const ACCEPT = preload("res://scripts/sim/phase2/n158_direct_threaded_acceptance.gd")

func _initialize() -> void:
    var first: Dictionary = _source(100, 5, 2)
    var at300: Dictionary = _source(300, 9, 3)
    var at600: Dictionary = _source(600, 12, 5)
    var at900: Dictionary = _source(900, 16, 7)
    var previous: Dictionary = {}
    for checkpoint in [first, at300, at600, at900]:
        var tick: int = int(checkpoint["tick"])
        var response: Dictionary = {"ok": true, "tick": tick,
            "checkpoint": checkpoint.duplicate(true)}
        if not ACCEPT.verify_boundary(tick, checkpoint, response).get("accepted", false):
            _fail("exact parity rejected " + str(tick))
            return
        var counts: Dictionary = ACCEPT.compare_source_growth_boundary(
            tick, checkpoint, response["checkpoint"])
        if not counts.get("accepted", false):
            _fail("source boundary rejected " + str(tick))
            return
        if not previous.is_empty():
            var growth: Dictionary = ACCEPT.compare_source_growth(previous, counts)
            if not growth.get("accepted", false):
                _fail("source growth rejected " + str(tick))
                return
        previous = counts.duplicate(true)
        var altered: Dictionary = response.duplicate(true)
        altered["checkpoint"]["native_production"]["ledger"]["receipts"].append({"id": "extra"})
        if ACCEPT.verify_boundary(tick, checkpoint, altered).get("accepted", false):
            _fail("receipt divergence accepted " + str(tick))
            return
        altered = response.duplicate(true)
        altered["checkpoint"]["events"]["pending"].append({"id": "extra"})
        if ACCEPT.compare_source_growth_boundary(tick, checkpoint,
                altered["checkpoint"]).get("accepted", false):
            _fail("event divergence accepted " + str(tick))
            return
        altered = response.duplicate(true)
        altered["tick"] = tick - 1
        if ACCEPT.verify_boundary(tick, checkpoint, altered).get("accepted", false):
            _fail("wrong source clock accepted " + str(tick))
            return
    var previous_window: Dictionary = {}
    for end_tick in [100, 300, 600, 900]:
        var samples: Array = []
        for tick in range(end_tick - 99, end_tick + 1):
            samples.append({"valid": true, "paid_ticks": 1, "after_tick": tick,
                "advance_wall_usec": 40, "projection_wall_usec": 10,
                "request_wall_usec": 60, "direct_advance_wall_usec": 45})
        var window: Dictionary = ACCEPT.summarize_window(end_tick, samples)
        if not window.get("accepted", false):
            _fail("100 paid ticks rejected at " + str(end_tick) + " " + str(window))
            return
        if not previous_window.is_empty() and not ACCEPT.compare_late_windows(
                previous_window, window).get("accepted", false):
            _fail("independent windows rejected")
            return
        var skipped: Array = samples.duplicate(true)
        skipped[50]["after_tick"] += 1
        if ACCEPT.summarize_window(end_tick, skipped).get("accepted", false):
            _fail("missing paid tick accepted")
            return
        var invalid: Array = samples.duplicate(true)
        invalid[30]["request_wall_usec"] = 1
        if ACCEPT.summarize_window(end_tick, invalid).get("accepted", false):
            _fail("impossible request attribution accepted")
            return
        previous_window = window.duplicate(true)
    var forged: Dictionary = previous.duplicate(true)
    forged["counts"]["tick"] = 600
    if ACCEPT.compare_source_growth(
            ACCEPT.compare_source_growth_boundary(600, at600, at600.duplicate(true)),
            forged).get("accepted", false):
        _fail("forged 900 boundary accepted")
        return
    print("P2_PERF_E_900_DIRECT_THREADED_ORACLE_PASS")
    quit(0)

func _source(tick: int, receipt_count: int, event_count: int) -> Dictionary:
    var receipts: Array = []
    var events: Array = []
    for i in range(receipt_count):
        receipts.append({"id": "r" + str(i)})
    for i in range(event_count):
        events.append({"id": "e" + str(i)})
    return {"tick": tick, "native_production": {"ledger": {"receipts": receipts},
        "rng": [1, 2], "world": {"ships": {}, "facilities": {}}},
        "events": {"pending": events}, "bt": {"state": tick}}

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_900_DIRECT_THREADED_ORACLE_FAIL " + reason)
    quit(1)
