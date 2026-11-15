extends RefCounted
## N83: source-backed best_trade_route_with_ownership, data-only. No Buy/Sell mutations.
const MIN_TRADE_MARGIN := 0.10
const TRADE_QTY_DEFAULT := 50
const HALF_LIFE_TICKS := 1500.0
const FRESHNESS_FLOOR := 0.10

static func freshness(observed_tick: int, current_tick: int) -> float:
	var age: int = maxi(0, current_tick - observed_tick)
	return clampf(pow(2.0, -float(age) / HALF_LIFE_TICKS), FRESHNESS_FLOOR, 1.0)

static func median_known_price(knowledge: Dictionary, commodity: String) -> float:
	var prices: Array[float] = []
	for location in knowledge:
		var records: Dictionary = knowledge[location]
		if records.has(commodity):
			var p: float = float(records[commodity].get("price", NAN))
			if is_finite(p):
				prices.append(p)
	if prices.is_empty():
		return NAN
	prices.sort()
	return prices[prices.size() / 2] # Rust: upper middle for even lengths.

static func _owner_boost(ship_faction: String, owner: String) -> float:
	return 1.25 if not ship_faction.is_empty() and ship_faction == owner else 1.0

static func best_trade_route(knowledge: Dictionary, tick: int, ship_faction: String = "",
		controllers: Dictionary = {}, commerce_allowed: Dictionary = {},
		buyer_cash: Dictionary = {}, route_performance: Dictionary = {},
		require_buyer_ledger: bool = false) -> Dictionary:
	# Knowledge: location -> commodity -> {price,tick}.
	# commerce_allowed: location -> bool (prevalidated from native faction relations).
	# buyer_cash: destination location -> actual spendable market credits.
	# route_performance: "buy|sell|commodity" -> {attempts,avg_profit_per_unit}.
	# Read-only estimate; executor must revalidate stock, price, cash, docking.
	var locs: Array = knowledge.keys()
	locs.sort()
	var best: Dictionary = {}
	var best_margin := -INF
	for i in range(locs.size()):
		var a: String = str(locs[i])
		if not bool(commerce_allowed.get(a, true)):
			continue
		var pa: Dictionary = knowledge[a]
		for j in range(i + 1, locs.size()):
			var b: String = str(locs[j])
			if not bool(commerce_allowed.get(b, true)):
				continue
			var pb: Dictionary = knowledge[b]
			var goods: Array = pa.keys()
			goods.sort()
			for good in goods:
				if not pb.has(good):
					continue
				var first: Dictionary = pa[good]
				var second: Dictionary = pb[good]
				var price_a: float = float(first.get("price", NAN))
				var price_b: float = float(second.get("price", NAN))
				if not is_finite(price_a) or not is_finite(price_b) or price_a < 0.0 or price_b < 0.0:
					continue
				var buy: String = a if price_a < price_b else b
				var sell: String = b if price_a < price_b else a
				var lo: float = minf(price_a, price_b)
				var hi: float = maxf(price_a, price_b)
				if require_buyer_ledger:
					if not buyer_cash.has(sell):
						continue
					var available: float = float(buyer_cash[sell])
					var required: float = ceil(hi * float(TRADE_QTY_DEFAULT))
					if not is_finite(required) or required <= 0.0 or available < required:
						continue
				var fresh: float = minf(freshness(int(first.get("tick", 0)), tick), freshness(int(second.get("tick", 0)), tick))
				var raw_margin: float = (hi - lo) / maxf(lo, 1.0) * fresh
				var stats: Dictionary = route_performance.get(buy + "|" + sell + "|" + str(good), {})
				var learned := 1.0
				if int(stats.get("attempts", 0)) >= 3 and float(stats.get("avg_profit_per_unit", 0.0)) < (hi - lo) * 0.5:
					learned = 0.3
				var real_margin: float = raw_margin * learned
				var boost: float = (_owner_boost(ship_faction, str(controllers.get(buy, ""))) + _owner_boost(ship_faction, str(controllers.get(sell, "")))) / 2.0
				var margin: float = real_margin * boost
				if real_margin > MIN_TRADE_MARGIN and margin > best_margin:
					best_margin = margin
					best = {"commodity": str(good), "buy_location": buy, "sell_location": sell,
						"margin": margin, "raw_margin": real_margin,
						"quantity": TRADE_QTY_DEFAULT, "estimated_profit": roundi((hi - lo) * TRADE_QTY_DEFAULT)}
	return best
