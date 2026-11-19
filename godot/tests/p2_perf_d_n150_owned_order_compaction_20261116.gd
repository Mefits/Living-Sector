extends SceneTree
## PERF D: compare paid owned compaction with detached standalone oracle.
const Market = preload("res://scripts/sim/phase1/n150_native_full_market_tick.gd")

func _initialize() -> void:
	var source: Array = []
	for i in range(240):
		source.append({"agent_id": "market-old" if i % 17 == 0 else "agent-%d" % i,
			"placed_at_tick": 0 if i % 3 == 0 else 95,
			"payload": {"nested": [i]}})
	var expected: Dictionary = Market._retain_orders(source, 100, 20, false)
	var owned: Array = source.duplicate(true)
	var result: Dictionary = Market._retain_orders(owned, 100, 20, true)
	assert(expected.get("ok", false) and result.get("ok", false))
	assert(result["orders"] == expected["orders"])
	assert(owned == expected["orders"])
	assert(source.size() == 240)
	# A caller-owned source and returned standalone result must not alias.
	if not owned.is_empty():
		owned[0]["payload"]["nested"][0] = -777
		assert(source[1]["payload"]["nested"][0] != -777)
		assert(expected["orders"][0]["payload"]["nested"][0] != -777)
	# Retention must preserve stable order and not remove future orders.
	var future: Array = [{"agent_id": "agent-future", "placed_at_tick": 150}]
	assert(Market._retain_orders(future, 100, 20, true)["orders"].size() == 1)
	# Malformed orders must reject rather than silently drop or accept.
	for bad in [{"agent_id": 12, "placed_at_tick": 99},
			{"agent_id": "agent-bad", "placed_at_tick": -1},
			{"agent_id": "agent-bad", "placed_at_tick": "99"}]:
		var invalid: Array = [{"agent_id": "agent-ok", "placed_at_tick": 99}, bad]
		assert(not Market._retain_orders(invalid, 100, 20, true).get("ok", false))
	# A standalone result must detach even retained nested dictionaries.
	var detached: Array = [{"agent_id": "agent-ok", "placed_at_tick": 99,
		"payload": {"nested": [42]}}]
	var copy: Dictionary = Market._retain_orders(detached, 100, 20, false)
	copy["orders"][0]["payload"]["nested"][0] = 9
	assert(detached[0]["payload"]["nested"][0] == 42)
	print("PASS p2_perf_d_n150_owned_order_compaction_20261116")
	quit(0)
