extends RefCounted
## N10: native Rust price_engine.rs parity; all prices are CR, no wallet mutation.
const Catalog = preload("res://scripts/sim/economy/commodity_catalog.gd")
const ABSOLUTE_PRICE_CEILING := 500.0
const URGENCY_ONSET_TICKS := 20
const URGENCY_RAMP_TICKS := 50
const URGENCY_MAX_MULTIPLIER := 2.5
const MAX_PRICE_CHANGE_PER_TICK := 0.05

static func urgency_multiplier(shortage_ticks: int) -> float:
    if shortage_ticks <= URGENCY_ONSET_TICKS:
        return 1.0
    return minf(1.0 + float(shortage_ticks - URGENCY_ONSET_TICKS) / float(URGENCY_RAMP_TICKS), URGENCY_MAX_MULTIPLIER)

static func coverage_to_pressure(coverage: float) -> float:
    if coverage < 0.5:
        return 1.0
    if coverage < 2.0:
        return 0.6 + (2.0 - coverage) / 4.0 * 0.4
    if coverage < 10.0:
        return (10.0 - coverage) / 20.0
    if coverage < 200.0:
        return 0.0
    if coverage < 1000.0:
        return -0.2
    if coverage < 10000.0:
        return -0.5
    return -1.0

static func recalculate(current_price: float, supply: float, demand: float, elasticity: float, shortage_ticks: int) -> float:
    if not is_finite(current_price) or current_price <= 0.0 or not is_finite(supply) or supply < 0.0 or not is_finite(demand) or demand < 0.0 or not is_finite(elasticity) or elasticity < 0.0 or shortage_ticks < 0:
        return -1.0
    var pressure := coverage_to_pressure(supply / maxf(demand, 1.0))
    var effective_elasticity := elasticity * urgency_multiplier(shortage_ticks) if pressure > 0.0 else elasticity
    var change := clampf(pressure * effective_elasticity, -MAX_PRICE_CHANGE_PER_TICK, MAX_PRICE_CHANGE_PER_TICK)
    var new_price := current_price * (1.0 + change)
    if not is_finite(new_price):
        return -1.0
    return clampf(floorf(new_price * 100.0 + 0.5) / 100.0, 1.0, ABSOLUTE_PRICE_CEILING)

static func apply_spread(base_price: float, spread: float) -> Dictionary:
    if not is_finite(base_price) or base_price <= 0.0 or not is_finite(spread) or spread < 0.0 or spread >= 2.0:
        return {}
    var buy := base_price * (1.0 + spread / 2.0)
    var sell := base_price * (1.0 - spread / 2.0)
    if not is_finite(buy) or not is_finite(sell):
        return {}
    return {"buy": floorf(buy * 100.0 + 0.5) / 100.0, "sell": floorf(sell * 100.0 + 0.5) / 100.0}

## Each market owns a separate mutable price map. This is an atomic tick:
## invalid inputs abort without partially repricing any commodity.
static func reprice_market(prices: Dictionary, stocks: Dictionary, demand: Dictionary, elasticity: float, shortage_ticks: Dictionary) -> bool:
    var next_prices := prices.duplicate(true)
    for slug in prices:
        if typeof(slug) != TYPE_STRING or not Catalog.contains(slug):
            return false
        var ticks: Variant = shortage_ticks.get(slug, 0)
        if typeof(ticks) != TYPE_INT:
            return false
        var price := recalculate(float(prices[slug]), float(stocks.get(slug, 0.0)), float(demand.get(slug, 0.0)), elasticity, ticks)
        if price < 0.0:
            return false
        next_prices[slug] = price
    prices.clear()
    prices.merge(next_prices)
    return true
