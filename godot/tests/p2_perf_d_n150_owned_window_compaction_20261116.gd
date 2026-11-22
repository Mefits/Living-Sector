extends SceneTree
## D regression: owned N150 consumption windows retain exact source order.
const N150 = preload("res://scripts/sim/phase1/n150_native_full_market_tick.gd")

func _initialize() -> void:
	var source := {
		"id": "market-a", "facility_location": "loc-a",
		"pricing": {"prices": {"ore": 20.0}, "supply": {"ore": 100.0},
			"demand": {"ore": 1.0}, "price_elasticity": 0.1, "spread": 0.05},
		"flow": {"seed_demand": {"ore": 1.0},
			"consumption_window": {"ore": [
				{"tick": 1, "qty": 2.0, "nested": {"v": 1}},
				{"tick": 10, "qty": 3.0, "nested": {"v": 2}},
				{"tick": 20, "qty": 4.0, "nested": {"v": 3}},
				{"tick": 30, "qty": 5.0, "nested": {"v": 4}}]}},
		"orders": {"pending_buys": [], "pending_sells": [],
			"reserved": {}, "order_expiry_ticks": 50},
		"history": {"shortage_ticks": {}, "trend_samples": [],
			"spawned_at_tick": 1, "last_tick": 1}
	}
	# At tick 120, cutoff=20. Entries 20 and 30 must remain in
	# original order and demand must sum in the same order (4+5).
	var original: Dictionary = source.duplicate(true)
	var price_fn := func(price: float, _stock: float, _demand: float,
			_elasticity: float, _shortage: int) -> float: return price
	var result: Dictionary = N150.tick_one_market(source, 120, 1, price_fn)
	assert(result.get("ok", false), str(result.get("reason", "")))
	var next: Dictionary = result["market"]
	var entries: Array = next["flow"]["consumption_window"]["ore"]
	assert(entries.size() == 2)
	assert(int(entries[0]["tick"]) == 20 and int(entries[1]["tick"]) == 30)
	assert(float(next["pricing"]["demand"]["ore"]) == 9.0)
	assert(source == original)
	entries[0]["nested"]["v"] = 99
	assert(int(source["flow"]["consumption_window"]["ore"][2]["nested"]["v"]) == 3)
	# A malformed retained sample must fail closed without mutating source.
	var invalid: Dictionary = source.duplicate(true)
	invalid["flow"]["consumption_window"]["ore"][2]["qty"] = "bad"
	var invalid_before: Dictionary = invalid.duplicate(true)
	var rejected: Dictionary = N150.tick_one_market(invalid, 120, 1, price_fn)
	assert(not rejected.get("ok", false))
	assert(rejected.get("reason") == "invalid_consumption_sample")
	assert(invalid == invalid_before)
	print("PASS p2_perf_d_n150_owned_window_compaction_20261116")
	quit()
