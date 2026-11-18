extends SceneTree
## E: real detached checkpoint-size acceptance; never touches live N39.
const ACCEPT = preload("res://scripts/sim/phase2/n158_direct_threaded_acceptance.gd")

func _initialize() -> void:
    var early: Dictionary = _checkpoint(100, 2, 1, 1, 2)
    var worker: Dictionary = early.duplicate(true)
    var good: Dictionary = ACCEPT.compare_size_boundary(100, early, worker)
    if not good.get("accepted", false):
        _fail("same checkpoint rejected " + str(good))
        return
    # No mutable alias retained in the result.
    early["native_production"]["world"]["facilities"]["dock"]["dock_queue"].append("later")
    if good["counts"]["dock_waiting"] != 1:
        _fail("size result retained mutable World alias")
        return
    early = _checkpoint(100, 2, 1, 1, 2)
    var mismatches: Array = [
        ["ships", "ship-3"],
        ["dock", "ship-3"],
        ["contracts", "contract-2"],
        ["receipts", "receipt-3"]
    ]
    for kind in mismatches:
        var changed: Dictionary = worker.duplicate(true)
        var world: Dictionary = changed["native_production"]["world"]
        match kind[0]:
            "ships":
                world["ships"][kind[1]] = {}
            "dock":
                world["facilities"]["dock"]["dock_queue"].append(kind[1])
            "contracts":
                world["contract_board"]["contracts"][kind[1]] = {}
            "receipts":
                world["dock_receipts"][kind[1]] = {}
        if ACCEPT.compare_size_boundary(100, early, changed).get("accepted", false):
            _fail("size mismatch accepted: " + str(kind[0]))
            return
    var malformed: Dictionary = worker.duplicate(true)
    malformed["tick"] = 99
    if ACCEPT.compare_size_boundary(100, early, malformed).get("accepted", false):
        _fail("wrong SourceClock accepted")
        return
    malformed = worker.duplicate(true)
    malformed["native_production"].erase("world")
    if ACCEPT.compare_size_boundary(100, early, malformed).get("accepted", false):
        _fail("missing authoritative World accepted")
        return
    malformed = worker.duplicate(true)
    malformed["native_production"]["world"]["facilities"]["dock"]["dock_queue"] = "bad"
    if ACCEPT.compare_size_boundary(100, early, malformed).get("accepted", false):
        _fail("invalid dock shape accepted")
        return
    if ACCEPT.compare_size_boundary(200, early, worker).get("accepted", false):
        _fail("unsupported boundary accepted")
        return
    var late: Dictionary = _checkpoint(300, 4, 3, 2, 5)
    var late_pair: Dictionary = ACCEPT.compare_size_boundary(300, late, late.duplicate(true))
    var growth: Dictionary = ACCEPT.compare_size_growth(good, late_pair)
    if not growth.get("accepted", false):
        _fail("valid size growth rejected " + str(growth))
        return
    if growth["delta"]["ships"] != 2 or growth["delta"]["dock_waiting"] != 2 or (
            growth["delta"]["contracts"] != 1 or
            growth["delta"]["receipt_categories"]["dock_receipts"] != 3):
        _fail("growth counters incorrect")
        return
    if ACCEPT.compare_size_growth(late_pair, good).get("accepted", false):
        _fail("reversed growth accepted")
        return
    var forged: Dictionary = late_pair.duplicate(true)
    forged["counts"]["receipt_categories"].erase("dock_receipts")
    if ACCEPT.compare_size_growth(good, forged).get("accepted", false):
        _fail("missing receipt category silently counted as zero")
        return
    forged = late_pair.duplicate(true)
    forged["counts"]["missing"].append("new_unknown_domain")
    if ACCEPT.compare_size_growth(good, forged).get("accepted", false):
        _fail("changed coverage accepted")
        return
    print("P2_PERF_E_DIRECT_THREADED_SIZE_PARITY_PASS")
    quit(0)

func _checkpoint(tick: int, ship_count: int, waiting: int,
        contracts: int, receipts: int) -> Dictionary:
    var world: Dictionary = {"ships": {}, "facilities": {"dock": {"dock_queue": []}},
        "contract_board": {"contracts": {}}, "dock_receipts": {}}
    for i in range(ship_count):
        world["ships"]["ship-" + str(i)] = {}
    for i in range(waiting):
        world["facilities"]["dock"]["dock_queue"].append("ship-" + str(i))
    for i in range(contracts):
        world["contract_board"]["contracts"]["contract-" + str(i)] = {}
    for i in range(receipts):
        world["dock_receipts"]["receipt-" + str(i)] = {}
    return {"tick": tick, "native_production": {"world": world}}

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_DIRECT_THREADED_SIZE_PARITY_FAIL " + reason)
    quit(1)
