extends RefCounted
## Frozen Rust: native/crates/sim_core/src/ai/considerations.rs
## Pure, side-effect-free inputs. Each output is {axis, value}; never modifies cargo or credits.
const HALF_LIFE_TICKS := 1500.0
const FRESHNESS_FLOOR := 0.10

static func _c(v: float) -> float:
	return clampf(v, 0.0, 1.0)

static func _value(axis: String, value: float) -> Dictionary:
	return {"axis": axis, "value": _c(value)}

static func fuel_urgency(fuel: float, capacity: float) -> Dictionary:
	return _value("safety", 1.0 - (fuel / capacity if capacity > 0.0 else 0.0))

static func price_freshness(observed_tick: int, current_tick: int) -> float:
	var age := maxi(0, current_tick - observed_tick)
	return clampf(pow(2.0, -float(age) / HALF_LIFE_TICKS), FRESHNESS_FLOOR, 1.0)

## price_knowledge: location -> commodity -> {price, tick}.
static func trade_opportunity(price_knowledge: Dictionary, current_tick: int) -> Dictionary:
	if price_knowledge.size() < 2:
		return _value("profit", 0.0)
	var locations := price_knowledge.keys()
	var max_margin := 0.0
	for i in range(locations.size()):
		var a: Dictionary = price_knowledge[locations[i]]
		for j in range(i + 1, locations.size()):
			var b: Dictionary = price_knowledge[locations[j]]
			for commodity in a:
				if not b.has(commodity):
					continue
				var x: Dictionary = a[commodity]
				var y: Dictionary = b[commodity]
				var lo: float = minf(float(x.get("price", 0.0)), float(y.get("price", 0.0)))
				var hi: float = maxf(float(x.get("price", 0.0)), float(y.get("price", 0.0)))
				var freshness: float = minf(price_freshness(int(x.get("tick", 0)), current_tick), price_freshness(int(y.get("tick", 0)), current_tick))
				max_margin = maxf(max_margin, (hi - lo) / maxf(lo, 1.0) * freshness)
	return _value("profit", max_margin / 2.0)

static func cargo_opportunity(cargo: Dictionary, capacity: int) -> Dictionary:
	var used := 0
	for quantity in cargo.values():
		used += int(quantity)
	return _value("profit", float(maxi(0, capacity - used)) / float(maxi(1, capacity)))

static func cargo_to_sell(cargo: Dictionary, capacity: int) -> Dictionary:
	var used := 0
	for quantity in cargo.values():
		used += int(quantity)
	return _value("profit", float(used) / float(maxi(1, capacity)))

static func financial_pressure(credits: int) -> Dictionary:
	if credits <= 0:
		return _value("safety", 1.0)
	if credits < 500:
		return _value("safety", 0.8)
	if credits < 2000:
		return _value("safety", 0.4)
	if credits < 10000:
		return _value("safety", 0.1)
	return _value("safety", 0.0)

static func exploration_desire(visited: Array, price_knowledge: Dictionary) -> Dictionary:
	if visited.is_empty() or price_knowledge.is_empty():
		return _value("exploration", 0.3)
	var visited_set := {}
	for location in visited:
		visited_set[location] = true
	var unknown := 0
	for location in price_knowledge:
		if not visited_set.has(location):
			unknown += 1
	return _value("exploration", float(unknown) / float(price_knowledge.size()))

static func docked_at_facility(docked_at: Variant) -> Dictionary:
	return _value("safety", 0.0 if docked_at == null else 1.0)
