extends SceneTree
## Run headless with --script res://tests/p2_perf_d_n150_empty_orders_20261117.gd
const N150 = preload("res://scripts/sim/phase1/n150_native_full_market_tick.gd")

func _initialize() -> void:
    var empty: Array = []
    var owned: Dictionary = N150._retain_orders(empty, 120, 50, true)
    assert(owned.get("ok", false))
    assert(owned["orders"].is_empty())
    var detached: Dictionary = N150._retain_orders(empty, 120, 50, false)
    assert(detached.get("ok", false))
    assert(detached["orders"].is_empty())
    var live: Array = [
        {"agent_id": "buyer-1", "placed_at_tick": 110, "meta": {"n": 1}},
        {"agent_id": "market-legacy", "placed_at_tick": 110},
        {"agent_id": "buyer-expired", "placed_at_tick": 1}
    ]
    var filtered: Dictionary = N150._retain_orders(live, 120, 50, false)
    assert(filtered.get("ok", false))
    assert(filtered["orders"].size() == 1)
    filtered["orders"][0]["meta"]["n"] = 99
    assert(live[0]["meta"]["n"] == 1)
    var invalid: Dictionary = N150._retain_orders([{"agent_id": "buyer"}], 120, 50, true)
    assert(not invalid.get("ok", true))
    print("P2 PERF D N150 empty orders PASS")
    quit()
