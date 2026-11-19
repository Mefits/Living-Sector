extends SceneTree
# Run: godot --headless --path godot --script res://tests/p2_perf_d_n135_commodity_index.gd
const Demand = preload("res://scripts/sim/phase2/unified_station_demand_phase.gd")
var failures: Array[String] = []

func _initialize() -> void:
    _test_order_and_reservations()
    _test_invalidation_and_negatives()
    if failures.is_empty():
        print("PASS p2_perf_d_n135_commodity_index")
        quit(0)
    else:
        for failure in failures:
            push_error(failure)
        quit(1)

func _check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)

func _station(id: String, loc: String, funds: int = 1000) -> Dictionary:
    return {"id": id, "location": loc, "faction": "F", "credits": funds}

func _market(owner: String, supply: Dictionary, prices: Dictionary = {}, consumption: Dictionary = {}) -> Dictionary:
    return {"owner": owner, "supply": supply, "prices": prices,
        "consumption_window": consumption}

# Independent old O(deficits * suppliers) oracle for the source scan.
# No commodity index: iterate every market in lexical location order.
func _legacy_sources(world: Dictionary, destination: String, good: String) -> Array:
    var locations: Array = world["markets"].keys()
    locations.sort()
    var result: Array = []
    for loc in locations:
        var market: Dictionary = world["markets"][loc]
        var owner: String = str(market.get("owner", ""))
        if not (world["facilities"].get(owner) is Dictionary):
            continue
        if str(world["facilities"][owner].get("location", "")) != str(loc):
            continue
        if str(loc) == destination:
            continue
        var amount = market["supply"].get(good, 0.0)
        if not (amount is int or amount is float):
            continue
        if float(amount) == 0.0:
            continue
        result.append(str(loc))
    return result

func _test_order_and_reservations() -> void:
    var world: Dictionary = {"facilities": {}, "markets": {}}
    world["facilities"]["dest"] = _station("dest", "Z", 35)
    world["markets"]["Z"] = _market("dest", {"ore": 0.0}, {"ore": 2.0},
        {"ore": [{"tick": 3, "qty": 20.0}]})
    for i in range(80):
        var loc: String = "S%03d" % i
        var owner: String = "f%03d" % i
        world["facilities"][owner] = _station(owner, loc)
        var stock: Dictionary = {"water": 100.0}
        if i == 3 or i == 7 or i == 11:
            stock["ore"] = 5.0
        world["markets"][loc] = _market(owner, stock)
    var original: Dictionary = world.duplicate(true)
    var result: Dictionary = Demand.propose(world, 3)
    _check(result.get("ok", false), "valid source roster rejected")
    var expected: Array = _legacy_sources(world, "Z", "ore")
    _check(expected == ["S003", "S007", "S011"], "legacy order fixture invalid")
    var selected: Array = []
    var total: int = 0
    for row in result.get("proposals", []):
        selected.append(str(row["source_location"]))
        total += int(row["quantity"])
        _check(int(row["estimated_cost"]) == 10, "price or quantity changed")
    _check(selected == expected, "indexed source order differs from full-scan oracle")
    _check(total == 15, "physical stock reservation changed")
    _check(result.get("blocked", []).size() == 1, "unfilled deficit lost")
    _check(world == original, "proposal mutated World")
    # The next call must see live owner/location and stock changes.
    world["facilities"]["f003"]["location"] = "MOVED"
    world["markets"]["S007"]["supply"]["ore"] = 0.0
    var changed: Dictionary = Demand.propose(world, 3)
    _check(changed.get("ok", false), "changed supplier roster rejected")
    _check(changed.get("proposals", []).size() == 1, "stale supplier index reused")
    if changed.get("proposals", []).size() == 1:
        _check(changed["proposals"][0]["source_location"] == "S011", "incorrect live source")

func _test_invalidation_and_negatives() -> void:
    var world: Dictionary = {"facilities": {
        "d": _station("d", "B"), "s": _station("s", "A")},
        "markets": {
            "B": _market("d", {"ore": 0.0}, {"ore": 2.0},
                {"ore": [{"tick": 4, "qty": 3.0}]}),
            "A": _market("s", {"ore": -2.0})}}
    var bad: Dictionary = Demand.propose(world, 4)
    _check(not bad.get("ok", true) and bad.get("reason") == "invalid_supplier_stock",
        "negative stock was skipped by index")
    world["markets"]["A"]["supply"]["ore"] = INF
    bad = Demand.propose(world, 4)
    _check(not bad.get("ok", true) and bad.get("reason") == "invalid_supplier_stock",
        "nonfinite stock was skipped by index")
    world["markets"]["A"]["supply"]["ore"] = 4.0
    world["facilities"]["s"]["location"] = "C"
    var changed: Dictionary = Demand.propose(world, 4)
    _check(changed.get("ok", false) and changed.get("proposals", []).is_empty(),
        "moved owner still offered stock")
    world["facilities"]["s"]["location"] = "A"
    world["markets"]["A"]["owner"] = "missing"
    bad = Demand.propose(world, 4)
    _check(not bad.get("ok", true) and bad.get("reason") == "missing_actual_station_owner",
        "invalid destination/source market preflight lost")
