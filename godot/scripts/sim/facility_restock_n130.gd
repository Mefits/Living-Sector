extends RefCounted
## Frozen Rust: sim_core/src/agents/facility/restock.rs::tick_restock.
## Inputs are exclusive snapshots. External coordinator commits all balances/stock atomically.
static func plan(buyer: Dictionary, seller: Dictionary, market: Dictionary, commodities: Array, threshold: float, target: float, commerce_allowed: bool) -> Dictionary:
	if not commerce_allowed or bool(buyer.get("abandoned", false)) or bool(seller.get("abandoned", false)):
		return {"ok": false, "reason": "commerce_blocked"}
	if str(buyer.get("location", "")) != str(market.get("location", "")) or str(seller.get("location", "")) != str(market.get("location", "")):
		return {"ok": false, "reason": "location_mismatch"}
	var internal := str(buyer.get("id", "")) == str(seller.get("id", ""))
	var buyer_after := buyer.duplicate(true)
	var seller_after := seller.duplicate(true)
	var market_after := market.duplicate(true)
	var reserves: Dictionary = buyer_after.get("reserves", {}).duplicate(true)
	var supply: Dictionary = market_after.get("supply", {}).duplicate(true)
	var prices: Dictionary = market_after.get("prices", {})
	var remaining := int(buyer.get("credits", 0))
	var purchases: Array = []
	for commodity in commodities:
		var current := float(reserves.get(commodity, 0.0))
		var available := float(supply.get(commodity, 0.0))
		if not is_finite(current) or not is_finite(available) or current < 0.0 or current >= threshold or available < 1.0:
			continue
		var quantity := floorf(minf(target - current, available))
		var cost := 0
		if not internal:
			var price := float(prices.get(commodity, 0.0))
			if not is_finite(price) or price <= 0.0 or remaining <= 0:
				continue
			quantity = minf(quantity, floorf(float(remaining) / price))
			if quantity < 1.0:
				continue
			var raw_cost: float = ceil(quantity * price)
			if not is_finite(raw_cost) or raw_cost > 9223372036854775807.0:
				continue
			cost = int(raw_cost)
			if cost <= 0 or cost > remaining:
				continue
		if quantity < 1.0:
			continue
		remaining -= cost
		reserves[commodity] = current + quantity
		supply[commodity] = available - quantity
		purchases.append({"commodity": commodity, "quantity": quantity, "cost": cost})
	if purchases.is_empty():
		return {"ok": true, "changed": false, "purchases": []}
	var total := int(buyer.get("credits", 0)) - remaining
	if not internal and int(seller.get("credits", 0)) > 9223372036854775807 - total:
		return {"ok": false, "reason": "seller_overflow"}
	buyer_after["reserves"] = reserves
	buyer_after["credits"] = remaining
	buyer_after["dirty"] = true
	if not internal:
		seller_after["credits"] = int(seller["credits"]) + total
		seller_after["dirty"] = true
	else:
		seller_after = buyer_after.duplicate(true)
	market_after["supply"] = supply
	market_after["dirty"] = true
	return {"ok": true, "changed": true, "buyer": buyer_after, "seller": seller_after, "market": market_after, "purchases": purchases}
