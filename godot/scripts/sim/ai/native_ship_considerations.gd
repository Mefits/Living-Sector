extends RefCounted
## N137: pure Rust ai/considerations.rs port. CODE_UNVERIFIED.
## Input snapshots are read-only Dictionaries; no game state, money or cargo is mutated.
## Consideration shape: {"value": float in [0,1], "axis": String}.
## Price memory: {location: {commodity: {"price": float, "tick": int}}}.
## Ship components: fuel {fuel, fuel_capacity}, cargo {cargo:{commodity:count}, capacity},
## economy {credits}, memory {price_knowledge, visited}, position {docked_at}.
## Axis names match native personality.rs and utility.rs.
const HALF_LIFE_TICKS: float = 1500.0
const FRESHNESS_FLOOR: float = 0.10
const MAX_U32: int = 4294967295

static func _consideration(value: float, axis: String) -> Dictionary:
	return {"value": clampf(value, 0.0, 1.0), "axis": axis}

static func fuel_urgency(fuel: Dictionary) -> Dictionary:
	var capacity := float(fuel.get("fuel_capacity", 0.0))
	var fraction := float(fuel.get("fuel", 0.0)) / capacity if capacity > 0.0 else 0.0
	return _consideration(1.0 - fraction, "safety")

static func price_freshness_weight(observed_tick: int, current_tick: int) -> float:
	# Rust saturating_sub(u64), exp2(-age/1500), floor 0.10.
	var age := maxi(current_tick - observed_tick, 0)
	return clampf(pow(2.0, -float(age) / HALF_LIFE_TICKS), FRESHNESS_FLOOR, 1.0)

static func trade_opportunity(memory: Dictionary, current_tick: int) -> Dictionary:
	var knowledge: Dictionary = memory.get("price_knowledge", {})
	if knowledge.size() < 2:
		return _consideration(0.0, "profit")
	var locations := knowledge.keys()
	var max_margin := 0.0
	for i in range(locations.size()):
		var a: Dictionary = knowledge.get(locations[i], {})
		for j in range(i + 1, locations.size()):
			var b: Dictionary = knowledge.get(locations[j], {})
			for commodity in a:
				if not b.has(commodity):
					continue
				var quote_a: Dictionary = a[commodity]
				var quote_b: Dictionary = b[commodity]
				var price_a := float(quote_a.get("price", 0.0))
				var price_b := float(quote_b.get("price", 0.0))
				var lo := minf(price_a, price_b)
				var hi := maxf(price_a, price_b)
				var freshness := minf(
					price_freshness_weight(int(quote_a.get("tick", 0)), current_tick),
					price_freshness_weight(int(quote_b.get("tick", 0)), current_tick)
				)
				var margin := (hi - lo) / maxf(lo, 1.0) * freshness
				max_margin = maxf(max_margin, margin)
	return _consideration(max_margin / 2.0, "profit")

static func _cargo_used(cargo: Dictionary) -> int:
	var quantities: Dictionary = cargo.get("cargo", {})
	var used := 0
	for commodity in quantities:
		# Native ShipCargo uses u32 amounts and sum. Caller must supply valid native amounts.
		used += int(quantities[commodity])
	return used

static func cargo_opportunity(cargo: Dictionary) -> Dictionary:
	var capacity := int(cargo.get("capacity", 0))
	var free := maxi(capacity - _cargo_used(cargo), 0)
	return _consideration(float(free) / float(maxi(capacity, 1)), "profit")

static func cargo_to_sell(cargo: Dictionary) -> Dictionary:
	var capacity := int(cargo.get("capacity", 0))
	return _consideration(float(_cargo_used(cargo)) / float(maxi(capacity, 1)), "profit")

static func financial_pressure(economy: Dictionary) -> Dictionary:
	var credits := int(economy.get("credits", 0))
	var pressure := 0.0
	if credits <= 0:
		pressure = 1.0
	elif credits < 500:
		pressure = 0.8
	elif credits < 2000:
		pressure = 0.4
	elif credits < 10000:
		pressure = 0.1
	return _consideration(pressure, "safety")

static func exploration_desire(memory: Dictionary) -> Dictionary:
	var visited: Array = memory.get("visited", [])
	var knowledge: Dictionary = memory.get("price_knowledge", {})
	if visited.is_empty() or knowledge.is_empty():
		return _consideration(0.3, "exploration")
	var visited_set := {}
	for location in visited:
		visited_set[location] = true
	var unvisited := 0
	for location in knowledge:
		if not visited_set.has(location):
			unvisited += 1
	return _consideration(float(unvisited) / float(knowledge.size()), "exploration")

static func docked_at_facility(position: Dictionary) -> Dictionary:
	return _consideration(1.0 if position.get("docked_at", null) != null else 0.0, "safety")

static func snapshot_all(
	fuel: Dictionary,
	cargo: Dictionary,
	economy: Dictionary,
	memory: Dictionary,
	position: Dictionary,
	current_tick: int
) -> Dictionary:
	# Named values can feed native Utility scorer N85 without creating per-ship Nodes.
	# Caller may use trade_opportunity as trade_profit when composing native ActionSpec.
	return {
		"fuel_urgency": fuel_urgency(fuel),
		"trade_opportunity": trade_opportunity(memory, current_tick),
		"cargo_opportunity": cargo_opportunity(cargo),
		"cargo_to_sell": cargo_to_sell(cargo),
		"financial_pressure": financial_pressure(economy),
		"exploration_desire": exploration_desire(memory),
		"docked_at_facility": docked_at_facility(position)
	}
