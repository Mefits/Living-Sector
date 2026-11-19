extends SceneTree
## Astra II-C D: compare bounded sample-boundary copy with the legacy full
## history copy followed by source's exact append-and-trim behavior.
const MarketTick = preload("res://scripts/sim/phase1/n150_native_full_market_tick.gd")
const Price = preload("res://scripts/sim/economy/native_price_engine.gd")

func _market(count: int) -> Dictionary:
	var trends: Array = []
	for i in range(count):
		trends.append({"tick": i, "prices": {"ore": float(i)},
			"supply": {"ore": 8.0}, "extra": {"nested": [i]}})
	return {"id": "market", "facility_location": "earth",
		"pricing": {"prices": {"ore": 5.0}, "supply": {"ore": 8.0},
			"demand": {"ore": 2.0}, "price_elasticity": 0.5, "spread": 0.1},
		"flow": {"seed_demand": {"ore": 2.0}, "consumption_window": {
			"ore": [{"tick": 1000, "qty": 3.0}]}},
		"orders": {"pending_buys": [{"agent_id": "buyer", "placed_at_tick": 1000}],
			"pending_sells": [], "reserved": {"ore": 1.0}, "order_expiry_ticks": 50},
		"history": {"shortage_ticks": {"ore": 0}, "trend_samples": trends,
			"spawned_at_tick": 0, "last_tick": 1000,
			"extra": {"nested": [1, 2]}},
		"extension": {"nested": [{"value": 5}]}}

func _initialize() -> void:
	for count in [0, 1, 199, 200, 201, 1200]:
		var source: Dictionary = _market(count)
		var legacy_input: Dictionary = source.duplicate(true)
		# Equivalent to the old deep-copy-then-append-and-trim sequence:
		# remove only the prefix that will be discarded on this sample tick.
		if count >= 200:
			legacy_input["history"]["trend_samples"] = (
				legacy_input["history"]["trend_samples"].slice(count - 199))
		var actual: Dictionary = MarketTick.tick_one_market(
			source, 1008, 1, Callable(Price, "recalculate"))
		var oracle: Dictionary = MarketTick.tick_one_market(
			legacy_input, 1008, 1, Callable(Price, "recalculate"))
		assert(actual.get("ok", false), str(actual.get("reason", "")))
		assert(oracle.get("ok", false), str(oracle.get("reason", "")))
		assert(actual == oracle, "sample-boundary exact result parity")
		actual["market"]["history"]["trend_samples"].append({"tick": -1})
		actual["market"]["history"]["extra"]["nested"][0] = -1
		actual["market"]["extension"]["nested"][0]["value"] = -1
		assert(source["history"]["trend_samples"].size() == count)
		assert(source["history"]["extra"]["nested"][0] == 1)
		assert(source["extension"]["nested"][0]["value"] == 5)
		var non_sample: Dictionary = MarketTick.tick_one_market(
			source, 1009, 1, Callable(Price, "recalculate"))
		assert(non_sample.get("ok", false))
		assert(non_sample["market"]["history"]["trend_samples"].size() == count)
	var malformed: Dictionary = _market(1200)
	malformed["history"]["shortage_ticks"]["ore"] = -1
	var rejected: Dictionary = MarketTick.tick_one_market(
		malformed, 1008, 1, Callable(Price, "recalculate"))
	assert(not rejected.get("ok", true))
	assert(rejected.get("reason") == "invalid_shortage_counter")
	assert(malformed["history"]["trend_samples"].size() == 1200)
	quit(0)
