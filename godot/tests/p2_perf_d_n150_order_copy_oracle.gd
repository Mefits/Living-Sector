extends SceneTree
## Standalone regression for the N150 owned-stage order copy boundary.
const Market = preload("res://scripts/sim/phase1/n150_native_full_market_tick.gd")

func _initialize() -> void:
	var source: Array = [
		{"agent_id": "buyer-a", "placed_at_tick": 10, "payload": {"lots": [1, 2]}},
		{"agent_id": "market-legacy", "placed_at_tick": 20, "payload": {"lots": [3]}},
		{"agent_id": "buyer-expired", "placed_at_tick": 1, "payload": {"lots": [4]}},
		{"agent_id": "buyer-future", "placed_at_tick": 100, "payload": {"lots": [5]}}
	]
	var detached: Dictionary = Market._retain_orders(source, 30, 25)
	var owned_input: Array = source.duplicate(true)
	var owned: Dictionary = Market._retain_orders(owned_input, 30, 25, true)
	assert(detached.get("ok", false) and owned.get("ok", false))
	assert(detached["orders"] == owned["orders"])
	assert(detached["orders"].size() == 2)
	assert(detached["orders"][0]["agent_id"] == "buyer-a")
	assert(detached["orders"][1]["agent_id"] == "buyer-future")
	# Default public helper must detach nested payloads.
	detached["orders"][0]["payload"]["lots"].append(99)
	assert(source[0]["payload"]["lots"] == [1, 2])
	# Internal owned-stage helper can reuse the already detached order rows.
	owned["orders"][0]["payload"]["lots"].append(88)
	assert(owned_input[0]["payload"]["lots"] == [1, 2, 88])
	assert(source[0]["payload"]["lots"] == [1, 2])
	# Invalid rows must reject atomically without changing their input.
	var invalid: Array = [{"agent_id": "buyer", "placed_at_tick": "wrong"}]
	var before: Array = invalid.duplicate(true)
	assert(not Market._retain_orders(invalid, 30, 25, true).get("ok", false))
	assert(invalid == before)
	print("p2_perf_d_n150_order_copy_oracle: PASS")
	quit(0)
