extends SceneTree
## N152 GROWTH HYPOTHESIS / TEST_UNVERIFIED.
## godot --headless --path godot --script res://tests/p2_perf_growth_n152_refund_history_prefilter.gd
const Lifecycle = preload("res://scripts/sim/phase2/unified_n152_contract_lifecycle.gd")

func _initialize() -> void:
    var history: Dictionary = {}
    for n in range(1500):
        history["closed-%04d" % n] = {
            "status": "paid" if n % 2 == 0 else "expired",
            "reserved": 0, "receipt": {"nested": [n]}}
    history["z-refund"] = {"status": "expired", "reserved": 9}
    history["a-refund"] = {"status": "paid", "reserved": 2}
    history["m-active"] = {"status": "accepted", "reserved": 99}
    history["b-posted"] = {"status": "posted", "reserved": 99}
    var original: Dictionary = history.duplicate(true)
    # Reference oracle: old N152 scanned ALL sorted historical IDs,
    # then copied only paid/expired contracts with positive escrow.
    var expected: Array = []
    var all_ids: Array = history.keys()
    all_ids.sort()
    for id in all_ids:
        var c: Dictionary = history[id]
        if str(c.get("status", "")) in ["paid", "expired"] and int(c.get("reserved", 0)) > 0:
            expected.append(id)
    assert(expected == ["a-refund", "z-refund"])
    var actual: Array = Lifecycle._refundable_ids(history)
    assert(actual == expected, "must retain exact lexical refund order")
    assert(history == original, "candidate lookup must not mutate audit history")
    # Negative: a closed but already refunded contract cannot emit a
    # duplicate receipt; neither can an active escrow-funded contract.
    history["a-refund"]["reserved"] = 0
    assert(Lifecycle._refundable_ids(history) == ["z-refund"],
        "zero-reserve history must never trigger duplicate refund")
    history["z-refund"]["status"] = "accepted"
    assert(Lifecycle._refundable_ids(history).is_empty(),
        "active contracts must never be refunded by close pass")
    assert(history.size() == original.size(),
        "historical rows must remain intact for N38/ledger audit")
    quit(0)
