extends RefCounted
## Frozen Rust: ship/behavior.rs profitable_mining_quantity and cargo_liquidation_target.
## Pure policy; never debits ice, fuel or market cash.
const U32_MAX := 4294967295
const I64_MAX := 9223372036854775807

static func profitable_mining_quantity(cargo_free: int, available_ice: int, unit_price: float, buyer_credits: int, distance: int, fuel_rate: float, fuel_price: float, speed_modifier: float) -> Dictionary:
	if not is_finite(unit_price) or unit_price <= 0.0 or not is_finite(fuel_rate) or fuel_rate < 0.0 or not is_finite(fuel_price) or fuel_price < 0.0 or not is_finite(speed_modifier) or speed_modifier <= 0.0 or buyer_credits <= 0 or distance < 0:
		return {"ok": false, "reason": "invalid_or_insolvent"}
	var payable := mini(U32_MAX, int(floor(float(buyer_credits) / unit_price)))
	var qty := mini(mini(maxi(0, cargo_free), 40), mini(maxi(0, available_ice), payable))
	if qty <= 0:
		return {"ok": false, "reason": "no_payable_ice"}
	var revenue := floor(unit_price * float(qty))
	var trip_cost := 2.0 * float(distance) * fuel_rate * fuel_price / speed_modifier
	var net := revenue - trip_cost
	if not is_finite(net) or net < 1.0 or net >= float(I64_MAX):
		return {"ok": false, "reason": "unprofitable"}
	return {"ok": true, "quantity": qty, "estimated_net": int(floor(net))}

static func cargo_liquidation_target(at: String, cargo: Dictionary, price_memory: Dictionary, buyers: Dictionary, distances: Dictionary, commerce_allowed: Dictionary, multipliers: Dictionary) -> Dictionary:
	## buyers[location] = {owner, credits}; distances[location] = shortest path from at.
	## multipliers[owner] = native market_buy_multiplier including reputation.
	var choices := []
	var locations := buyers.keys()
	locations.sort()
	for location in locations:
		var buyer: Dictionary = buyers[location]
		var owner := str(buyer.get("owner", ""))
		var cash := int(buyer.get("credits", 0))
		if cash <= 0 or not bool(commerce_allowed.get(owner, false)):
			continue
		var prices: Dictionary = price_memory.get(location, {})
		var commodities := cargo.keys()
		commodities.sort()
		for commodity in commodities:
			var qty := int(cargo[commodity])
			if qty <= 0 or not prices.has(commodity):
				continue
			var price := float(prices[commodity]) * float(multipliers.get(owner, 1.0))
			if is_finite(price) and price > 0.0 and ceil(price * float(qty)) <= float(cash):
				if location == at or distances.has(location):
					var distance := 0 if location == at else int(distances[location])
					if distance >= 0:
						choices.append({"location": location, "distance": distance, "credits": cash, "commodity": commodity})
			break # Rust SellAll checks only first known positive commodity.
	choices.sort_custom(func(a, b):
		if a["distance"] != b["distance"]:
			return a["distance"] < b["distance"]
		if a["credits"] != b["credits"]:
			return a["credits"] > b["credits"]
		return str(a["location"]) < str(b["location"])
	)
	if choices.is_empty():
		return {"ok": false, "reason": "no_solvent_reachable_buyer"}
	return {"ok": true, "choice": choices[0]}
