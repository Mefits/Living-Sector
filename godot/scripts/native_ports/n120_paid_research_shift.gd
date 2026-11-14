extends RefCounted
## Port of strategy/director.rs research(): one local paid research shift.
## Returns a complete mutation proposal; external transaction authority applies atomically.
static func propose(faction_id: String, tick: int, commander: Dictionary, treasury: int, markets: Array, people: Array, authorization: Dictionary) -> Dictionary:
	if commander.is_empty():
		return {"ok": false, "reason": "missing_commander"}
	if commander.get("last_research_tick") != null and int(commander["last_research_tick"]) >= tick:
		return {"ok": false, "reason": "already_researched"}
	if str(commander.get("research", "")).is_empty():
		return {"ok": false, "reason": "research_complete"}
	if bool(commander.get("crisis", false)):
		return {"ok": false, "reason": "survival_first"}
	var ordered := markets.duplicate(true)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("location", "")) < str(b.get("location", "")))
	for market in ordered:
		if str(market.get("owner_faction", "")) != faction_id or str(market.get("facility_type", "")) != "station":
			continue
		var supply := float(market.get("electronics_supply", 0.0))
		var price := float(market.get("electronics_price", -1.0))
		if not is_finite(supply) or supply < 1.0 or not is_finite(price) or price < 0.0 or price > 10000.0:
			continue
		var cost := int(ceil(price)) + 10
		if treasury < cost + 10000:
			return {"ok": false, "reason": "research_reserve"}
		if not bool(authorization.get("allowed", false)) or cost > int(authorization.get("max_cost", -1)):
			return {"ok": false, "reason": "research_mandate_denied"}
		var eligible: Array = []
		for person in people:
			if str(person.get("faction_id", "")) != faction_id or str(person.get("location", "")) != str(market.get("location", "")):
				continue
			var available := int(person.get("population_count", 0)) * 3 / 5 - int(person.get("occupied_workers", 0))
			if available >= 10:
				eligible.append(person)
		eligible.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("id", "")) < str(b.get("id", "")))
		if eligible.is_empty():
			continue
		var person: Dictionary = eligible[0]
		var required := int(commander.get("research_required", 0))
		var progress := int(commander.get("progress", 0)) + 10
		var completed := required > 0 and progress >= required
		return {"ok": true, "cost": cost, "faction_id": faction_id, "tick": tick,
			"market_id": market.get("id"), "facility_id": market.get("facility_id"),
			"population_id": person.get("id"), "electronics_delta": -1.0,
			"treasury_delta": -cost, "facility_credits_delta": cost - 10,
			"population_wealth_delta": 10, "workers": 10,
			"research_progress": progress, "last_research_tick": tick,
			"completed_technology": commander.get("research") if completed else null,
			"work_shift": {"tick": tick, "workers": [[person.get("id"), 10]],
				"wages": 10, "input_payment": cost - 10, "processing_fee": 0}}
	return {"ok": false, "reason": "needs_local_electronics_and_free_workers"}
