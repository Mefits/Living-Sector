extends SceneTree
## Astra II-C/D: fused owned N150 window aggregation versus legacy two-pass oracle.
const Market = preload("res://scripts/sim/phase1/n150_native_full_market_tick.gd")

func _initialize() -> void:
    var failures: Array[String] = []
    for count in [0, 1, 50, 500, 1200]:
        for tick in [1, 100, 101, 400]:
            _case(count, tick, failures)
    _negative(failures)
    if not failures.is_empty():
        for message in failures:
            push_error(message)
        quit(1)
        return
    print("PASS p2_perf_d_n150_window_single_pass")
    quit(0)

func _price(price: float, _stock: float, _demand: float,
        _elasticity: float, _shortage: int) -> float:
    return price

func _market(count: int) -> Dictionary:
    var rows: Array = []
    for i in range(count):
        rows.append({"tick": i % 150, "qty": float(i % 11) / 7.0,
            "extension": {"nested": [i, {"value": i}]}})
    return {
        "id": "m1", "facility_location": "earth",
        "pricing": {"prices": {"ore": 12.0, "ice": 9.0},
            "supply": {"ore": 40.0, "ice": 50.0},
            "demand": {"ore": 1.0}, "price_elasticity": 0.1, "spread": 0.05},
        "flow": {"seed_demand": {"ore": 1.0, "ice": 2.0},
            "consumption_window": {"ore": rows, "ice": [
                {"tick": 100, "qty": 0.125}, {"tick": 101, "qty": 0.25}]}},
        "orders": {"pending_buys": [], "pending_sells": [],
            "reserved": {}, "order_expiry_ticks": 50},
        "history": {"shortage_ticks": {"ore": 0, "ice": 0},
            "trend_samples": [], "spawned_at_tick": 0, "last_tick": 0}
    }

func _legacy_window(rows: Array, cutoff: int) -> Dictionary:
    var retained: Array = []
    var amount: float = 0.0
    for original in rows.duplicate(true):
        if int(original["tick"]) < cutoff:
            continue
        retained.append(original)
        amount += float(original["qty"])
    return {"rows": retained, "amount": amount}

func _case(count: int, tick: int, failures: Array[String]) -> void:
    var source: Dictionary = _market(count)
    var before: Dictionary = source.duplicate(true)
    var output: Dictionary = Market.tick_one_market(
        source, tick, 1, Callable(self, "_price"))
    if not output.get("ok", false):
        failures.append("valid market rejected count=%d tick=%d" % [count, tick])
        return
    var result: Dictionary = output["market"]
    var cutoff: int = maxi(0, tick - 100)
    for slug in ["ore", "ice"]:
        var expected: Dictionary = _legacy_window(
            before["flow"]["consumption_window"][slug], cutoff)
        var actual: Array = result["flow"]["consumption_window"][slug]
        if actual != expected["rows"]:
            failures.append("window mismatch %s count=%d tick=%d" % [slug, count, tick])
        var seed: float = float(before["flow"]["seed_demand"][slug])
        var amount: float = float(expected["amount"])
        var expected_demand: float = maxf(amount, seed) if tick < 50 else (amount if amount > 0.0 else seed)
        if result["pricing"]["demand"].get(slug) != expected_demand:
            failures.append("demand mismatch %s count=%d tick=%d" % [slug, count, tick])
    if result["pricing"]["prices"] != before["pricing"]["prices"]:
        failures.append("prices changed")
    if source != before:
        failures.append("source changed")
    if not result["flow"]["consumption_window"]["ore"].is_empty():
        result["flow"]["consumption_window"]["ore"][0]["extension"]["nested"][1]["value"] = -1
        if source != before:
            failures.append("retained sample aliases World")

func _negative(failures: Array[String]) -> void:
    var bad: Dictionary = _market(0)
    bad["flow"]["consumption_window"]["ore"] = [
        {"tick": 0, "qty": "invalid"}]
    var original: Dictionary = bad.duplicate(true)
    var result: Dictionary = Market.tick_one_market(
        bad, 400, 1, Callable(self, "_price"))
    if result.get("ok", true) or result.get("reason", "") != "invalid_consumption_sample":
        failures.append("expired malformed sample accepted")
    if bad != original:
        failures.append("rejected tick mutated source")
    bad = _market(0)
    bad["flow"]["consumption_window"]["ore"] = "invalid"
    result = Market.tick_one_market(bad, 400, 1, Callable(self, "_price"))
    if result.get("ok", true) or result.get("reason", "") != "invalid_native_consumption_window":
        failures.append("invalid window type accepted")
