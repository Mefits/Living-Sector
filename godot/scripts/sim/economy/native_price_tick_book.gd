extends RefCounted
## CODE_UNVERIFIED. One price tick per market, using existing N10 Rust formula.
## No credit transfers or inventory mutation. Caller supplies actual stock/demand.
const Engine = preload("res://scripts/sim/economy/native_price_engine.gd")
var _markets: Dictionary = {}
var _last_tick: Dictionary = {}

func import_markets(markets: Dictionary) -> bool:
	if not _markets.is_empty():
		return false
	if not _valid(markets, {}):
		return false
	_markets = markets.duplicate(true)
	for id in _markets:
		_last_tick[id] = -1
	return true

## All-or-nothing across markets; a replay cannot reprice twice.
func tick(tick_id: int, stocks: Dictionary, demands: Dictionary, elasticities: Dictionary, shortages: Dictionary) -> Dictionary:
	if tick_id < 0 or stocks.size() != _markets.size() or demands.size() != _markets.size():
		return {"ok": false, "reason": "invalid_tick"}
	var next := _markets.duplicate(true)
	var ids := next.keys()
	ids.sort()
	for id in ids:
		if tick_id <= int(_last_tick[id]) or not stocks.has(id) or not demands.has(id) or not elasticities.has(id) or not shortages.has(id):
			return {"ok": false, "reason": "missing_or_replayed_market"}
		if typeof(stocks[id]) != TYPE_DICTIONARY or typeof(demands[id]) != TYPE_DICTIONARY or typeof(shortages[id]) != TYPE_DICTIONARY:
			return {"ok": false, "reason": "invalid_inputs"}
		if not Engine.reprice_market(next[id], stocks[id], demands[id], float(elasticities[id]), shortages[id]):
			return {"ok": false, "reason": "price_rejected"}
	_markets = next
	for id in ids:
		_last_tick[id] = tick_id
	return {"ok": true, "tick": tick_id}

func prices(market_id: String) -> Dictionary:
	return _markets.get(market_id, {}).duplicate(true)

func snapshot() -> Dictionary:
	return {"version": 1, "markets": _markets.duplicate(true), "last_tick": _last_tick.duplicate(true)}

func restore(state: Dictionary) -> bool:
	if state.get("version") != 1 or typeof(state.get("markets")) != TYPE_DICTIONARY or typeof(state.get("last_tick")) != TYPE_DICTIONARY:
		return false
	var markets: Dictionary = state["markets"]
	var ticks: Dictionary = state["last_tick"]
	if not _valid(markets, ticks):
		return false
	_markets = markets.duplicate(true)
	_last_tick = ticks.duplicate(true)
	return true

func _valid(markets: Dictionary, ticks: Dictionary) -> bool:
	if markets.is_empty():
		return false
	for id in markets:
		if typeof(id) != TYPE_STRING or id.is_empty() or typeof(markets[id]) != TYPE_DICTIONARY or markets[id].is_empty():
			return false
		if not ticks.is_empty() and (not ticks.has(id) or typeof(ticks[id]) != TYPE_INT or ticks[id] < -1):
			return false
		for slug in markets[id]:
			if typeof(slug) != TYPE_STRING or (typeof(markets[id][slug]) != TYPE_FLOAT and typeof(markets[id][slug]) != TYPE_INT) or Engine.recalculate(float(markets[id][slug]), 10.0, 1.0, 0.0, 0) <= 0.0:
				return false
	return ticks.is_empty() or ticks.size() == markets.size()
