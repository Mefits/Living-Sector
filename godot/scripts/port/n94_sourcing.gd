extends RefCounted
## N94 — read-only native strategy/sourcing.rs port.
## Caller provides authoritative market snapshots and relation treaties.
## No purchases, contracts, credits or inventory are mutated.

static func buy_multiplier(faction: String, owner: String, reputation: int, treaty: String) -> float:
	var rep: int = 50 if owner.is_empty() else (100 if faction != "" and faction == owner else reputation)
	var base: float = clampf(1.0 + (50.0 - float(rep)) * 0.005, 0.75, 1.25)
	if faction != "" and owner != "" and faction != owner and treaty in ["hostile", "war"] and base > 1.0:
		return 1.0 + (base - 1.0) * 2.0
	return base

static func purchase_cost(price: float, quantity: int, faction: String, owner: String, reputation: int, treaty: String) -> Dictionary:
	if not is_finite(price) or quantity < 0 or quantity > 2147483647:
		return {"ok": false}
	var unit: float = price * buy_multiplier(faction, owner, reputation, treaty)
	var cost: float = ceil(unit * float(quantity))
	if not is_finite(unit) or unit <= 0.0 or not is_finite(cost) or cost >= 9223372036854775807.0:
		return {"ok": false}
	return {"ok": true, "cost": int(cost)}

## markets: location -> {prices: {commodity: float}, supply: {commodity: float}}
## owners: location -> faction; treaties: "buyer|owner" -> treaty string.
static func choose(faction: String, destination: String, commodity: String, quantity: int, reward: int, markets: Dictionary, owners: Dictionary, treaties: Dictionary) -> Dictionary:
	var has_stock := false
	var best: Dictionary = {}
	var locations: Array = markets.keys()
	locations.sort()
	for location_value in locations:
		var location: String = str(location_value)
		if location == destination:
			continue
		var owner: String = str(owners.get(location, ""))
		var treaty: String = str(treaties.get(faction + "|" + owner, treaties.get(owner + "|" + faction, "neutral")))
		if owner != faction and treaty in ["hostile", "war"]:
			continue
		var market: Dictionary = markets[location]
		var stock: float = float(market.get("supply", {}).get(commodity, 0.0))
		if not is_finite(stock) or stock < float(quantity):
			continue
		has_stock = true
		var quote: Dictionary = purchase_cost(float(market.get("prices", {}).get(commodity, 0.0)), quantity, faction, owner, 0, treaty)
		if not quote.get("ok", false) or int(quote.cost) >= reward:
			continue
		var own: int = 0 if owner == faction else 1
		if best.is_empty() or own < int(best.own) or (own == int(best.own) and (int(quote.cost) < int(best.cost) or (int(quote.cost) == int(best.cost) and location < str(best.location)))):
			best = {"location": location, "cost": quote.cost, "own": own}
	if best.is_empty():
		return {"ok": false, "reason": "unprofitable_source" if has_stock else "no_accessible_stock"}
	return {"ok": true, "location": best.location, "cost": best.cost}

## Only POSTED, non-passenger, fixed-reward contracts are candidates.
## Caller owns the ContractBoard and must expire/refund exactly once in its economic frame.
static func unprofitable_posted(contracts: Array, markets: Dictionary, owners: Dictionary, treaties: Dictionary) -> Array:
	var withdrawn: Array = []
	for contract_value in contracts:
		var c: Dictionary = contract_value
		if str(c.get("status", "")) != "posted" or str(c.get("contract_type", "")) == "passenger" or not c.has("fixed_strategy_reward"):
			continue
		var location: String = str(c.get("source_location", ""))
		if not markets.has(location):
			continue
		var market: Dictionary = markets[location]
		var owner: String = str(owners.get(location, ""))
		var faction: String = str(c.get("requestor_id", ""))
		var treaty: String = str(treaties.get(faction + "|" + owner, treaties.get(owner + "|" + faction, "neutral")))
		var quote: Dictionary = purchase_cost(float(market.get("prices", {}).get(str(c.get("commodity", "")), 0.0)), int(c.get("quantity", 0)), faction, owner, 100, treaty)
		var reward: int = int(c.fixed_strategy_reward)
		if not quote.get("ok", false) or int(quote.cost) >= reward:
			withdrawn.append({"contract_id": str(c.get("id", "")), "minimum_purchase_cost": quote.get("cost", null), "reward": reward, "reason": "unprofitable_source"})
	withdrawn.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.contract_id) < str(b.contract_id))
	return withdrawn
