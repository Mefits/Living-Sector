extends RefCounted
## N10: deterministic per-market price history; observations only, no trades.
## Caller supplies a native market ID and simulation tick (not frame time).
const Price = preload("res://scripts/sim/economy/native_price_engine.gd")
const Catalog = preload("res://scripts/sim/economy/commodity_catalog.gd")
var market_id: String
var prices: Dictionary = {}
var observations: Array = []
var last_tick: int = -1
var history_limit: int = 256

func _init(id: String = "", initial_prices: Dictionary = {}, limit: int = 256) -> void:
    market_id = id
    history_limit = maxi(limit, 1)
    for slug in initial_prices:
        if Catalog.contains(str(slug)) and is_finite(float(initial_prices[slug])) and float(initial_prices[slug]) > 0.0:
            prices[slug] = float(initial_prices[slug])

## Each tick may be recorded once. No price mutation if invalid data.
func advance(tick: int, stocks: Dictionary, demand: Dictionary, elasticity: float, shortage_ticks: Dictionary) -> bool:
    if market_id.is_empty() or tick <= last_tick or tick < 0:
        return false
    if not Price.reprice_market(prices, stocks, demand, elasticity, shortage_ticks):
        return false
    last_tick = tick
    var keys: Array = prices.keys()
    keys.sort()
    var snapshot := {}
    for slug in keys:
        snapshot[slug] = prices[slug]
    observations.append({"tick": tick, "prices": snapshot})
    while observations.size() > history_limit:
        observations.pop_front()
    return true

func snapshot() -> Dictionary:
    return {"market_id": market_id, "last_tick": last_tick, "prices": prices.duplicate(true), "observations": observations.duplicate(true), "history_limit": history_limit}
