extends SceneTree
## Targeted N150 wire_snapshot oracle: order, malformed row, and deep detachment.
const MarketTick = preload("res://scripts/sim/phase1/n150_native_full_market_tick.gd")

func _initialize() -> void:
	var market: Dictionary = {
		"id": "m", "facility_location": "earth",
		"pricing": {"prices": {"ore": 5.0}, "supply": {"ore": 10.0},
			"demand": {"ore": 3.0}, "price_elasticity": 0.5, "spread": 0.1},
		"flow": {"seed_demand": {}, "consumption_window": {}},
		"orders": {"pending_buys": [], "pending_sells": [], "reserved": {},
			"order_expiry_ticks": 50},
		"history": {"shortage_ticks": {}, "trend_samples": [
			{"tick": 2, "prices": {"ore": 5.0}, "supply": {"ore": 10.0}},
			{"tick": 1, "prices": {"ore": 4.0}, "supply": {"ore": 9.0}}],
			"spawned_at_tick": 0, "last_tick": 2}
	}
	var result: Dictionary = MarketTick.wire_snapshot(market)
	assert(result.get("ok", false))
	var trends: Array = result["snapshot"]["trend_samples"]
	assert(trends.size() == 2)
	assert(trends[0]["tick"] == 2 and trends[1]["tick"] == 1)
	trends[0]["prices"]["ore"] = 999.0
	assert(market["history"]["trend_samples"][0]["prices"]["ore"] == 5.0)
	market["history"]["trend_samples"][1]["supply"]["ore"] = 777.0
	assert(trends[1]["supply"]["ore"] == 9.0)
	var broken: Dictionary = market.duplicate(true)
	broken["history"]["trend_samples"].append(7)
	var rejected: Dictionary = MarketTick.wire_snapshot(broken)
	assert(not rejected.get("ok", false))
	assert(rejected.get("reason", "") == "invalid_trend_sample")
	quit(0)
