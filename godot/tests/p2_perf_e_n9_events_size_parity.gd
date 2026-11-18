extends SceneTree
## PERF E: detached authoritative N9 journal and Source event size oracle.
const ACCEPT = preload("res://scripts/sim/phase2/n158_direct_threaded_acceptance.gd")

func _initialize() -> void:
    var early: Dictionary = _checkpoint(100, 2, 1)
    var worker: Dictionary = early.duplicate(true)
    var good: Dictionary = ACCEPT.compare_source_growth_boundary(100, early, worker)
    if not good.get("accepted", false):
        _fail("identical detached source counts rejected " + str(good))
        return
    # Returned counts must not alias either detached checkpoint.
    early["native_production"]["ledger"]["receipts"].append({"id": "later"})
    early["events"]["pending"].append({"id": "later"})
    if good["counts"]["n9_receipts"] != 2 or good["counts"]["source_pending_events"] != 1:
        _fail("mutable alias in source counters")
        return
    early = _checkpoint(100, 2, 1)
    for key in ["n9", "events", "receipt_shape", "event_shape", "missing_n9", "missing_events"]:
        var changed: Dictionary = worker.duplicate(true)
        match key:
            "n9":
                changed["native_production"]["ledger"]["receipts"].append({"id": "new"})
            "events":
                changed["events"]["pending"].append({"id": "new"})
            "receipt_shape":
                changed["native_production"]["ledger"]["receipts"] = "bad"
            "event_shape":
                changed["events"]["pending"] = {}
            "missing_n9":
                changed["native_production"].erase("ledger")
            "missing_events":
                changed.erase("events")
        if ACCEPT.compare_source_growth_boundary(100, early, changed).get("accepted", false):
            _fail("invalid source boundary accepted " + key)
            return
    var malformed: Dictionary = worker.duplicate(true)
    malformed["native_production"]["ledger"]["receipts"][0] = "not_a_receipt"
    if ACCEPT.compare_source_growth_boundary(100, early, malformed).get("accepted", false):
        _fail("malformed receipt accepted")
        return
    malformed = worker.duplicate(true)
    malformed["events"]["pending"][0] = "not_an_event"
    if ACCEPT.compare_source_growth_boundary(100, early, malformed).get("accepted", false):
        _fail("malformed event accepted")
        return
    malformed = worker.duplicate(true)
    malformed["tick"] = 99
    if ACCEPT.compare_source_growth_boundary(100, early, malformed).get("accepted", false):
        _fail("wrong SourceClock accepted")
        return
    var late: Dictionary = _checkpoint(300, 5, 4)
    var late_pair: Dictionary = ACCEPT.compare_source_growth_boundary(
        300, late, late.duplicate(true))
    var growth: Dictionary = ACCEPT.compare_source_growth(good, late_pair)
    if not growth.get("accepted", false) or growth["delta"]["n9_receipts"] != 3 or (
            growth["delta"]["source_pending_events"] != 3):
        _fail("correct source growth rejected " + str(growth))
        return
    if ACCEPT.compare_source_growth(late_pair, good).get("accepted", false):
        _fail("reversed boundaries accepted")
        return
    var forged: Dictionary = late_pair.duplicate(true)
    forged["counts"].erase("n9_receipts")
    if ACCEPT.compare_source_growth(good, forged).get("accepted", false):
        _fail("missing N9 count accepted")
        return
    forged = late_pair.duplicate(true)
    forged["counts"]["tick"] = 600
    if ACCEPT.compare_source_growth(good, forged).get("accepted", false):
        _fail("forged boundary tick accepted")
        return
    print("P2_PERF_E_N9_EVENTS_SIZE_PARITY_PASS")
    quit(0)

func _checkpoint(tick: int, n9: int, events: int) -> Dictionary:
    var receipts: Array = []
    var pending: Array = []
    for i in range(n9):
        receipts.append({"id": "receipt-" + str(i)})
    for i in range(events):
        pending.append({"id": "event-" + str(i)})
    return {"tick": tick, "native_production": {"ledger": {
        "version": 1, "receipts": receipts}},
        "events": {"next_sequence": events + 1, "pending": pending}}

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_N9_EVENTS_SIZE_PARITY_FAIL " + reason)
    quit(1)
