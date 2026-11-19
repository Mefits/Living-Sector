extends SceneTree
## Regression for N150 owned consumption-window filtering.
## Run with Godot --headless --path godot --script res://tests/p2_perf_d_n150_consumption_owned_samples.gd
const Market = preload("res://scripts/sim/phase1/n150_native_full_market_tick.gd")
const Price = preload("res://scripts/sim/economy/native_price_engine.gd")

func _initialize() -> void:
	var failures: int = 0
	for tick in [16, 51, 120, 240]:
		var source: Dictionary = _market()
		var untouched: Dictionary = source.duplicate(true)
		var result: Dictionary = Market.tick_one_market(source, tick, 1, Callable(Price, "recalculate"))
		failures += _check(result.get("ok", false), "tick succeeds " + str(tick))
		if not result.get("ok", false):
			continue
		var window: Array = result["market"]["flow"]["consumption_window"]["ore"]
		var expected: Array = []
		for sample in untouched["flow"]["consumption_window"]["ore"]:
			if int(sample["tick"]) >= maxi(0, tick - Market.DEMAND_WINDOW_BASE):
				expected.append(sample)
		failures += _check(window == expected, "window retains original order and cutoff")
		failures += _check(source == untouched, "source market never mutated")
		if not window.is_empty():
			window[0]["qty"] = 9999.0
			window[0]["meta"]["nested"] = "modified"
			failures += _check(source == untouched, "returned samples detached from source")
		var second: Dictionary = Market.tick_one_market(source, tick, 1, Callable(Price, "recalculate"))
		failures += _check(second.get("ok", false), "repeat succeeds")
		if second.get("ok", false):
			failures += _check(second["market"]["flow"]["consumption_window"]["ore"] == expected, "repeat is deterministic")
	var invalid: Dictionary = _market()
	invalid["flow"]["consumption_window"]["ore"].append({"tick": "wrong", "qty": 1.0})
	var original: Dictionary = invalid.duplicate(true)
	var rejected: Dictionary = Market.tick_one_market(invalid, 120, 1, Callable(Price, "recalculate"))
	failures += _check(not rejected.get("ok", true), "invalid sample rejected")
	failures += _check(invalid == original, "invalid sample leaves source intact")
	print("P2 PERF D N150 owned samples: ", "PASS" if failures == 0 else str(failures) + " FAILURES")
	quit(0 if failures == 0 else 1)

func _market() -> Dictionary:
	return {
		"id": "m-1", "facility_location": "earth",
		"pricing": {"prices": {"ore": 100.0}, "supply": {"ore": 100.0},
			"demand": {"ore": 2.0}, "price_elasticity": 0.02, "spread": 0.05},
		"flow": {"seed_demand": {"ore": 2.0},
			"consumption_window": {"ore": [
				{"tick": 0, "qty": 1.0, "meta": {"nested": "zero"}},
				{"tick": 16, "qty": 2.0, "meta": {"nested": "first"}},
				{"tick": 51, "qty": 3.0, "meta": {"nested": "second"}},
				{"tick": 120, "qty": 4.0, "meta": {"nested": "third"}}]}},
		"orders": {"pending_buys": [], "pending_sells": [],
			"reserved": {}, "order_expiry_ticks": 50},
		"history": {"shortage_ticks": {}, "trend_samples": [],
			"spawned_at_tick": 0, "last_tick": 0}
	}

func _check(condition: bool, description: String) -> int:
	if not condition:
		push_error("P2 PERF D N150: " + description)
		return 1
	return 0
