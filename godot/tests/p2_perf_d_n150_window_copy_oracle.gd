extends SceneTree
## Astra II-C: N150 paid market copy must match the old full-copy/compact
## algorithm, including exact demand/price and negative validation.
const N150 = preload("res://scripts/sim/phase1/n150_native_full_market_tick.gd")
const Price = preload("res://scripts/sim/economy/native_price_engine.gd")

func _market(count: int) -> Dictionary:
	var rows: Array = []
	for i in range(count):
		rows.append({"tick": i, "qty": float((i % 7) + 1),
			"extension": {"nested": [i]}})
	return {"id": "m", "facility_location": "earth",
		"pricing": {"prices": {"ore": 25.0}, "supply": {"ore": 8.0},
			"demand": {"ore": 3.0}, "price_elasticity": 0.2, "spread": 0.1},
		"flow": {"seed_demand": {"ore": 3.0},
			"consumption_window": {"ore": rows,
				"water": [{"tick": 1000, "qty": 2.0}]}},
		"orders": {"pending_buys": [], "pending_sells": [],
			"reserved": {}, "order_expiry_ticks": 50},
		"history": {"shortage_ticks": {"ore": 0}, "trend_samples": [],
			"spawned_at_tick": 0, "last_tick": 1}}

func _initialize() -> void:
	for tick in [120, 121, 128, 1008]:
		for count in [0, 1, 20, 200, 1200]:
			var source: Dictionary = _market(count)
			var before: Dictionary = source.duplicate(true)
			var legacy: Dictionary = source.duplicate(true)
			# Oracle: trim the input exactly as the old post-copy loop
			# would do, then run the same source price/demand machinery.
			var cutoff: int = maxi(0, tick - 100)
			for slug in legacy["flow"]["consumption_window"]:
				var kept: Array = []
				for entry in legacy["flow"]["consumption_window"][slug]:
					if int(entry["tick"]) >= cutoff:
						kept.append(entry)
				legacy["flow"]["consumption_window"][slug] = kept
			var actual: Dictionary = N150.tick_one_market(
				source, tick, 1, Callable(Price, "recalculate"))
			var expected: Dictionary = N150.tick_one_market(
				legacy, tick, 1, Callable(Price, "recalculate"))
			assert(actual.get("ok", false), str(actual.get("reason", "")))
			assert(expected.get("ok", false), str(expected.get("reason", "")))
			assert(actual == expected, "exact paid N150 result parity")
			assert(source == before, "no World mutation")
			var retained: Array = actual["market"]["flow"]["consumption_window"]["ore"]
			if not retained.is_empty():
				retained[0]["extension"]["nested"][0] = -999
				assert(source == before, "no mutable alias to source")
	# Even an expired invalid row must fail, never disappear silently.
	var malformed: Dictionary = _market(200)
	malformed["flow"]["consumption_window"]["ore"][0]["qty"] = "bad"
	var frozen: Dictionary = malformed.duplicate(true)
	var rejected: Dictionary = N150.tick_one_market(
		malformed, 1008, 1, Callable(Price, "recalculate"))
	assert(not rejected.get("ok", true))
	assert(rejected.get("reason") == "invalid_consumption_sample")
	assert(malformed == frozen)
	var wrong_window: Dictionary = _market(20)
	wrong_window["flow"]["consumption_window"]["ore"] = {}
	var bad_window: Dictionary = N150.tick_one_market(
		wrong_window, 120, 1, Callable(Price, "recalculate"))
	assert(not bad_window.get("ok", true))
	assert(bad_window.get("reason") == "invalid_native_consumption_window")
	print("PASS p2_perf_d_n150_window_copy_oracle")
	quit(0)
