extends RefCounted
## N125. Frozen Rust: agents/population.rs::post_food_contracts.
## Pure proposals. ContractBoard must atomically reserve payer funds and post.
const FOOD_THRESHOLD := 40
const EMERGENCY_THRESHOLD := 20
const FOOD_BASE_PRICE := 18.0
const PREMIUM := 1.8
const EMERGENCY_PREMIUM := 6.0
const URGENCY_PEAK := 2.0
const LIFESPAN_BASE := 200
const SOURCE_MIN_SUPPLY := 100.0

static func propose(populations: Array, markets: Array, active_contracts: Array, tick: int, tick_multiplier: int) -> Array[Dictionary]:
	var proposals: Array[Dictionary] = []
	if tick_multiplier <= 0 or tick < 0 or tick % (25 * tick_multiplier) != 0:
		return proposals
	var supplies: Dictionary = {}
	for market in markets:
		if not market is Dictionary:
			continue
		var loc := str(market.get("location", ""))
		if not loc.is_empty():
			supplies[loc] = float(market.get("food_supply", 0.0))
	for pop in populations:
		if not pop is Dictionary:
			continue
		var sat := int(pop.get("food_satisfaction", 100))
		var dest := str(pop.get("location", ""))
		var pop_id := str(pop.get("id", ""))
		if sat >= FOOD_THRESHOLD or dest.is_empty() or pop_id.is_empty():
			continue
		var duplicate := false
		for c in active_contracts:
			if c is Dictionary and str(c.get("destination", "")) == dest and str(c.get("commodity", "")) == "food" and str(c.get("status", "")) == "POSTED":
				duplicate = true
				break
		if duplicate:
			continue
		for pending in proposals:
			if pending["destination"] == dest:
				duplicate = true
				break
		if duplicate:
			continue
		var source := ""
		var best_supply := SOURCE_MIN_SUPPLY
		# Rust HashMap tie order is unspecified. Stable lexical tie break here.
		var locations: Array = supplies.keys()
		locations.sort()
		for location in locations:
			var available := float(supplies[location])
			if str(location) != dest and available > best_supply:
				source = str(location)
				best_supply = available
		if source.is_empty():
			continue
		var count := maxi(0, int(pop.get("population_count", 0)))
		var emergency := sat < EMERGENCY_THRESHOLD
		var quantity := clampi(int(count / (500 if emergency else 1000)), 50 if emergency else 20, 500 if emergency else 300)
		var payment := 0
		var lifespan := LIFESPAN_BASE * tick_multiplier
		if emergency:
			payment = int(FOOD_BASE_PRICE * EMERGENCY_PREMIUM * float(quantity))
			lifespan = maxi(int(LIFESPAN_BASE / 2), 50) * tick_multiplier
		else:
			var sat_ratio := clampf(float(sat) / 100.0, 0.0, 1.0)
			var urgency := 1.0 + (1.0 - sat_ratio) * URGENCY_PEAK
			payment = int(FOOD_BASE_PRICE * PREMIUM * urgency * float(quantity))
		proposals.append({
			"kind": "delivery", "requestor_id": pop_id,
			"faction_id": str(pop.get("faction_id", "")),
			"commodity": "food", "quantity": quantity,
			"source": source, "destination": dest, "payment": payment,
			"posted_tick": tick, "lifespan_ticks": lifespan,
			"emergency": emergency, "requires_authoritative_funding": true
		})
	return proposals
