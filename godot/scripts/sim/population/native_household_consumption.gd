extends RefCounted
## N71 CODE_UNVERIFIED. Rust agents/population.rs: consumption/purchase + sentiment.
## Opt-in independent snapshot; caller must supply actual native wallets and market stocks.
const BASE_INTERVAL := 5
const EMERGENCY_WATER_THRESHOLD := 30
const EMERGENCY_WATER_RATE := 0.5
const SHORTAGE_DROP := 5
const MET_RECOVERY := 2
const INERTIA := 0.9
var _populations: Dictionary = {}
var _markets: Dictionary = {}
var _last_tick := -1

func import_state(populations: Dictionary, markets: Dictionary) -> bool:
	if not _populations.is_empty() or not _markets.is_empty() or populations.is_empty():
		return false
	if not _valid(populations, markets):
		return false
	_populations = populations.duplicate(true)
	_markets = markets.duplicate(true)
	return true

func step(tick: int, multiplier: int, tick_scale: float) -> Dictionary:
	if tick < 0 or multiplier < 1 or not is_finite(tick_scale) or tick_scale < 0.0 or tick <= _last_tick:
		return {"ok": false, "reason": "invalid_or_replayed_tick"}
	if not _valid(_populations, _markets):
		return {"ok": false, "reason": "corrupt_state"}
	var next_p := _populations.duplicate(true)
	var next_m := _markets.duplicate(true)
	var receipts: Array = []
	if tick % (BASE_INTERVAL * multiplier) == 0:
		var ids := next_p.keys()
		ids.sort()
		for id in ids:
			var p: Dictionary = next_p[id]
			var loc: String = p.location
			if not next_m.has(loc):
				return {"ok": false, "reason": "missing_market", "population": id}
			var market: Dictionary = next_m[loc]
			var shortage := false
			var needs: Dictionary = {}
			for commodity in p.consumption:
				var amount: float = float(p.consumption[commodity]) * float(p.count) / 1000.0
				if amount > 0.0:
					needs[commodity] = amount
			if int(p.food_satisfaction) < EMERGENCY_WATER_THRESHOLD and int(p.count) > 0:
				needs["water"] = float(needs.get("water", 0.0)) + EMERGENCY_WATER_RATE * float(p.count) / 1000.0
			var goods := needs.keys()
			goods.sort()
			if goods.has("food"):
				goods.erase("food")
				goods.push_front("food")
			if goods.has("water"):
				goods.erase("water")
				goods.insert(1 if goods.has("food") else 0, "water")
			for commodity in goods:
				var needed: float = needs[commodity]
				var stock: float = float(market.stock.get(commodity, 0.0))
				var price: float = float(market.prices.get(commodity, 0.0))
				var cash: int = int(p.wallet)
				var qty := 0.0
				var paid := 0
				if stock > 0.0 and price > 0.0 and cash > 0:
					qty = minf(needed, minf(stock, float(cash) / price))
					paid = int(ceil(qty * price))
					while paid > cash and qty > 0.0:
						qty = maxf(0.0, qty - 0.000001)
						paid = int(ceil(qty * price))
					if qty > 0.0 and paid > 0:
						p.wallet = cash - paid
						market.seller_credits = int(market.seller_credits) + paid
						market.stock[commodity] = stock - qty
				if qty < needed - 0.000001:
					shortage = true
				receipts.append({"population": id, "commodity": commodity, "needed": needed, "quantity": qty, "payment": paid, "tick": tick})
			p.food_satisfaction = clampi(int(p.food_satisfaction) + (-SHORTAGE_DROP if shortage else MET_RECOVERY), 0, 100)
			var target := (int(p.food_satisfaction) * 6 + int(p.safety_satisfaction) * 2 + int(p.entertainment_satisfaction) * 2) / 10
			var inertia := pow(INERTIA, maxf(tick_scale, 0.01))
			p.overall_sentiment = roundi(float(p.overall_sentiment) * inertia + float(target) * (1.0 - inertia))
			p.unrest = clampi(100 - int(p.overall_sentiment), 0, 100)
			next_p[id] = p
			next_m[loc] = market
	_populations = next_p
	_markets = next_m
	_last_tick = tick
	return {"ok": true, "receipts": receipts}

func snapshot() -> Dictionary:
	return {"version": 1, "populations": _populations.duplicate(true), "markets": _markets.duplicate(true), "last_tick": _last_tick}

func restore(data: Dictionary) -> bool:
	if int(data.get("version", -1)) != 1 or typeof(data.get("populations")) != TYPE_DICTIONARY or typeof(data.get("markets")) != TYPE_DICTIONARY or typeof(data.get("last_tick")) != TYPE_INT:
		return false
	if not _valid(data.populations, data.markets):
		return false
	_populations = data.populations.duplicate(true)
	_markets = data.markets.duplicate(true)
	_last_tick = data.last_tick
	return true

func _valid(populations: Dictionary, markets: Dictionary) -> bool:
	for loc in markets:
		var m = markets[loc]
		if typeof(loc) != TYPE_STRING or typeof(m) != TYPE_DICTIONARY or not m.has("stock") or not m.has("prices") or not m.has("seller_credits") or int(m.seller_credits) < 0:
			return false
		for key in m.stock:
			if not m.prices.has(key) or not is_finite(float(m.stock[key])) or float(m.stock[key]) < 0.0 or not is_finite(float(m.prices[key])) or float(m.prices[key]) <= 0.0:
				return false
	for id in populations:
		var p = populations[id]
		if typeof(id) != TYPE_STRING or typeof(p) != TYPE_DICTIONARY:
			return false
		for key in ["location", "count", "wallet", "consumption", "food_satisfaction", "safety_satisfaction", "entertainment_satisfaction", "overall_sentiment"]:
			if not p.has(key):
				return false
		if not markets.has(p.location) or int(p.count) < 0 or int(p.wallet) < 0 or typeof(p.consumption) != TYPE_DICTIONARY:
			return false
		for key in p.consumption:
			if not is_finite(float(p.consumption[key])) or float(p.consumption[key]) < 0.0:
				return false
	return true
