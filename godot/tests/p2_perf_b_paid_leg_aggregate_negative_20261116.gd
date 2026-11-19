extends SceneTree
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
func _initialize() -> void:
    var money = Ledger.new()
    assert(money.import_accounts({"a": 100, "b": 10, "c": 0}))
    assert(money.transfer("op1", "a", "b", 20, 1, "trade")["ok"])
    assert(money.transfer("op2", "b", "c", 5, 2, "trade")["ok"])
    var before: Dictionary = money.snapshot()
    var result: Dictionary = money.paid_leg_totals_for_operations(["op1", "op2"])
    if not result.get("ok", false) or result["debits"] != 25 or result["credits"] != 25 or result["account_deltas"] != {"a": -20, "b": 15, "c": 5}:
        _fail("paid totals")
        return
    if money.paid_leg_totals_for_operations(["op2", "op1"]) != result:
        _fail("order-sensitive aggregate")
        return
    result["account_deltas"]["a"] = 999
    for ids in [[], ["op1", "op1"], ["op1", "missing"], [1], [""]]:
        if money.paid_leg_totals_for_operations(ids).get("ok", false):
            _fail("invalid proof accepted")
            return
    if money.snapshot() != before:
        _fail("mutable alias")
        return
    var fork = money.fork()
    assert(fork.transfer("op3", "a", "c", 2, 3, "trade")["ok"])
    if money.paid_leg_totals_for_operations(["op3"]).get("ok", false) or not fork.paid_leg_totals_for_operations(["op3"]).get("ok", false):
        _fail("fork isolation")
        return
    var restored = Ledger.new()
    if not restored.restore(before) or restored.paid_leg_totals_for_operations(["op1", "op2"])["account_deltas"] != {"a": -20, "b": 15, "c": 5}:
        _fail("N9 restore")
        return
    var writeoff = Ledger.new()
    assert(writeoff.import_accounts({"ship:x": 5}))
    assert(writeoff.close_removed_entity_account("decom", "ship:x", 1, "ship_decommissioned")["ok"])
    if writeoff.paid_leg_totals_for_operations(["decom"]).get("ok", false):
        _fail("writeoff accepted as paid transfer")
        return
    print("P2_PERF_B_PAID_LEG_AGGREGATE_PASS")
    quit(0)
func _fail(reason: String) -> void:
    push_error("P2_PERF_B_PAID_LEG_AGGREGATE_FAIL " + reason)
    quit(1)
