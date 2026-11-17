extends SceneTree
## N150 oversized restored trend history: same newest-200 order, detached output.
const MarketTick = preload("res://scripts/sim/phase1/n150_native_full_market_tick.gd")
const Price = preload("res://scripts/sim/economy/native_price_engine.gd")

func _initialize() -> void:
	var trends: Array = []
	for i in range(1000):
		trends.append({"tick": i, "prices": {"ore": float(i)}, "supply": {"ore": 10.0}})
	var market: Dictionary = {
		"id": "m", "facility_location": "earth",
		"pricing": {"prices": {"ore": 5.0}, "supply": {"ore": 10.0},
			"demand": {"ore": 3.0}, "price_elasticity": 0.5, "spread": 0.1},
		"flow": {"seed_demand": {}, "consumption_window": {}},
		"orders": {"pending_buys": [], "pending_sells": [], "reserved": {},
			"order_expiry_ticks": 50},
		"history": {"shortage_ticks": {}, "trend_samples": trends,
			"spawned_at_tick": 0, "last_tick": 999}
	}
	var result: Dictionary = MarketTick.tick_one_market(
		market, 1008, 1, Callable(Price, "recalculate"))
	assert(result.get("ok", false), str(result.get("reason", "")))
	var retained: Array = result["market"]["history"]["trend_samples"]
	assert(retained.size() == 200)
	assert(retained[0]["tick"] == 801)
	assert(retained[198]["tick"] == 999)
	assert(retained[199]["tick"] == 1008)
	retained[0]["prices"]["ore"] = -999.0
	assert(market["history"]["trend_samples"][801]["prices"]["ore"] == 801.0)
	assert(market["history"]["trend_samples"].size() == 1000)
	# A non-sampling tick must not truncate the existing source history.
	var untouched: Dictionary = MarketTick.tick_one_market(
		market, 1009, 1, Callable(Price, "recalculate"))
	assert(untouched.get("ok", false))
	assert(untouched["market"]["history"]["trend_samples"].size() == 1000)
	quit(0)
