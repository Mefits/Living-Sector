extends SceneTree
## Astra II-C/D: N150 order ownership and exact legacy retention oracle.
const Market = preload("res://scripts/sim/phase1/n150_native_full_market_tick.gd")

func _initialize() -> void:
    var failures: Array[String] = []
    for count in [0, 1, 51, 501, 1201]:
        for tick in [51, 100, 112]:
            _check_case(count, tick, failures)
    _check_negative(failures)
    if not failures.is_empty():
        for failure in failures:
            push_error(failure)
        quit(1)
        return
    print("PASS p2_perf_d_n150_expired_orders_owned_copy")
    quit(0)

func _price(price: float, _stock: float, _demand: float,
        _elasticity: float, _shortage: int) -> float:
    return price

func _fixture(count: int) -> Dictionary:
    var buys: Array = []
    var sells: Array = []
    for i in range(count):
        var order: Dictionary = {
            "agent_id": "market-legacy" if i % 7 == 0 else "ship-%04d" % i,
            "placed_at_tick": i % 125,
            "metadata": {"nested": [i, {"value": i * 2}]}}
        if i % 2 == 0:
            buys.append(order)
        else:
            sells.append(order)
    return {
        "id": "m1", "facility_location": "earth",
        "pricing": {
            "prices": {"ore": 12.0}, "supply": {"ore": 40.0},
            "demand": {"ore": 2.0}, "price_elasticity": 0.1,
            "spread": 0.05
        },
        "flow": {"seed_demand": {"ore": 2.0},
            "consumption_window": {"ore": [{"tick": 100, "qty": 1.5}]}},
        "orders": {"pending_buys": buys, "pending_sells": sells,
            "reserved": {"ore": 3.0}, "order_expiry_ticks": 50,
            "extension": {"list": [1, {"value": 2}]}},
        "history": {"shortage_ticks": {"ore": 0}, "trend_samples": [],
            "spawned_at_tick": 1, "last_tick": 0}
    }

func _legacy_retained(rows: Array, tick: int, expiry: int) -> Array:
    # Frozen paid path: deep-copy all rows first, then validate and compact.
    var copied: Array = rows.duplicate(true)
    var kept: Array = []
    for order in copied:
        if str(order["agent_id"]).begins_with("market-"):
            continue
        var age: int = tick - int(order["placed_at_tick"])
        if age < 0 or age < expiry:
            kept.append(order)
    return kept

func _check_case(count: int, tick: int, failures: Array[String]) -> void:
    var source: Dictionary = _fixture(count)
    var before: Dictionary = source.duplicate(true)
    var result: Dictionary = Market.tick_one_market(
        source, tick, 1, Callable(self, "_price"))
    if not result.get("ok", false):
        failures.append("valid market rejected count=%d tick=%d: %s" %
            [count, tick, str(result.get("reason", ""))])
        return
    var output: Dictionary = result["market"]
    for side in ["pending_buys", "pending_sells"]:
        var expected: Array = _legacy_retained(
            before["orders"][side], tick, 50)
        if output["orders"][side] != expected:
            failures.append("legacy order mismatch %s count=%d tick=%d" %
                [side, count, tick])
    if source != before:
        failures.append("source mutated count=%d tick=%d" % [count, tick])
    if output["pricing"]["prices"] != before["pricing"]["prices"]:
        failures.append("price changed count=%d tick=%d" % [count, tick])
    if output["pricing"]["supply"] != before["pricing"]["supply"]:
        failures.append("stock changed count=%d tick=%d" % [count, tick])
    if output["orders"]["reserved"] != before["orders"]["reserved"] or (
            output["orders"]["extension"] != before["orders"]["extension"]):
        failures.append("order metadata changed")
    output["orders"]["extension"]["list"][1]["value"] = -99
    if source["orders"]["extension"]["list"][1]["value"] != 2:
        failures.append("extension aliases source")
    for side in ["pending_buys", "pending_sells"]:
        if not output["orders"][side].is_empty():
            output["orders"][side][0]["metadata"]["nested"][1]["value"] = -5
            if source != before:
                failures.append("retained order aliases source")

func _check_negative(failures: Array[String]) -> void:
    # An expired malformed order MUST fail, not disappear silently.
    var malformed: Dictionary = _fixture(0)
    malformed["orders"]["pending_buys"].append({
        "agent_id": "ship-bad", "placed_at_tick": "0"})
    var before: Dictionary = malformed.duplicate(true)
    var result: Dictionary = Market.tick_one_market(
        malformed, 200, 1, Callable(self, "_price"))
    if result.get("ok", true) or result.get("reason") != "invalid_actual_order":
        failures.append("malformed expired order not rejected")
    if malformed != before:
        failures.append("rejected tick mutated source")
    # Reject invalid second-side rows after processing valid first-side rows.
    malformed = _fixture(20)
    malformed["orders"]["pending_sells"].append({
        "agent_id": "ship-bad", "placed_at_tick": -1})
    before = malformed.duplicate(true)
    result = Market.tick_one_market(malformed, 200, 1, Callable(self, "_price"))
    if result.get("ok", true) or result.get("reason") != "invalid_order_placed_at_tick":
        failures.append("negative sell order not rejected")
    if malformed != before:
        failures.append("negative sell mutated source")
