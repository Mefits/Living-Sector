extends RefCounted
## N126. Frozen Rust agents/population.rs::post_passenger_contracts.
## Does not create population, charge credits, or book escrow.
const MIN_POPULATION := 5000
const MIN_SENTIMENT := 50
const BATCH_SIZE := 50
const PAYMENT_PER_HEAD := 80
const CONTRACT_LIFESPAN_BASE := 200

static func propose(populations: Array, active_contracts: Array, tick: int, tick_multiplier: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if tick_multiplier <= 0 or tick < 0 or tick % (60 * tick_multiplier) != 0:
		return result
	var destinations: Array[String] = []
	for pop in populations:
		if pop is Dictionary:
			destinations.append(str(pop.get("location", "")))
	for pop in populations:
		if not pop is Dictionary:
			continue
		if int(pop.get("population_count", 0)) < MIN_POPULATION or int(pop.get("overall_sentiment", 0)) < MIN_SENTIMENT:
			continue
		var origin := str(pop.get("location", ""))
		var pop_id := str(pop.get("id", ""))
		if origin.is_empty() or pop_id.is_empty():
			continue
		var destination := ""
		# Rust picks the first different population location in ECS iteration order.
		for loc in destinations:
			if loc != origin and not loc.is_empty():
				destination = loc
				break
		if destination.is_empty():
			continue
		var already_active := false
		for c in active_contracts:
			if not c is Dictionary:
				continue
			if str(c.get("requestor_id", "")) == pop_id and str(c.get("contract_type", "")) == "passenger" and str(c.get("status", "")).to_upper() in ["POSTED", "ACCEPTED", "PICKED_UP"]:
				already_active = true
				break
		if already_active:
			continue
		result.append({
			"kind": "passenger", "requestor_id": pop_id,
			"faction_id": str(pop.get("faction_id", "")),
			"origin": origin, "destination": destination,
			"passenger_count": BATCH_SIZE,
			"payment": PAYMENT_PER_HEAD * BATCH_SIZE,
			"posted_tick": tick,
			"lifespan_ticks": CONTRACT_LIFESPAN_BASE * tick_multiplier,
			"requires_authoritative_funding": true,
			"requires_physical_transport": true
		})
	return result
