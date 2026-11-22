extends SceneTree
## Negative ownership oracle for N150 first-tick seed_demand transfer.
const N150 = preload("res://scripts/sim/phase1/n150_native_full_market_tick.gd")

static func _price(price: float, _stock: float, _demand: float, _elasticity: float, _shortage: int) -> float:
	return price

func _initialize() -> void:
	var original := {
		"id": "market-test", "facility_location": "earth",
		"pricing": {"prices": {"ore": 10.0}, "supply": {"ore": 100.0},
			"demand": {"ore": 4.0}, "price_elasticity": 0.1, "spread": 0.0},
		"flow": {"seed_demand": {}, "consumption_window": {}},
		"orders": {"pending_buys": [], "pending_sells": [],
			"reserved": {}, "order_expiry_ticks": 50},
		"history": {"shortage_ticks": {}, "trend_samples": [],
			"spawned_at_tick": null, "last_tick": 0}
	}
	var result: Dictionary = N150.tick_one_market(original, 1, 1, Callable(self, "_price"))
	assert(bool(result.get("ok", false)), str(result))
	var changed: Dictionary = result["market"]
	assert(changed["flow"]["seed_demand"] == {"ore": 4.0})
	assert(changed["pricing"]["demand"] == {"ore": 4.0})
	assert(original["flow"]["seed_demand"].is_empty())
	changed["flow"]["seed_demand"]["ore"] = 99.0
	assert(changed["pricing"]["demand"]["ore"] == 4.0)
	assert(original["pricing"]["demand"]["ore"] == 4.0)
	changed["pricing"]["demand"]["ore"] = 55.0
	assert(changed["flow"]["seed_demand"]["ore"] == 99.0)
	var second: Dictionary = N150.tick_one_market(changed, 2, 1, Callable(self, "_price"))
	assert(bool(second.get("ok", false)), str(second))
	assert(second["market"]["flow"]["seed_demand"]["ore"] == 99.0)
	assert(original["pricing"]["demand"]["ore"] == 4.0)
	print("PASS p2_perf_d_n150_owned_seed_transfer")
	quit(0)
