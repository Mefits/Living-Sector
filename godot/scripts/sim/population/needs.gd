extends RefCounted
## N12: population consumption slice from Rust agents/population.rs.
## Plain dictionaries are simulation state, not scene nodes. Call once per due tick.
## No household production: Rust requires a native employer for that path.
const CONSUMPTION_INTERVAL_BASE := 5
const FOOD_SAT_DROP_ON_SHORTAGE := 5
const FOOD_SAT_RECOVER_ON_MET := 2
const EMERGENCY_WATER_THRESHOLD := 30
const EMERGENCY_WATER_RATE := 0.5
const SENTIMENT_INERTIA_BASE := 0.9
const MIGRATION_SENTIMENT_FLOOR := 30
const MIGRATION_PRESSURE_RISE := 0.01
const MIGRATION_PRESSURE_DECAY := 0.005

## State shape:
## pop: id, facility_location, population_count, total_wealth, consumption
##      (slug -> units per 1000), food_satisfaction, safety_satisfaction,
##      entertainment_satisfaction, overall_sentiment, unrest, migration_pressure.
## market: facility_location, supply (slug -> units), prices (slug -> credits/unit),
##         seller_credits. Never mutate arguments when a preflight fails.
static func purchase(pop: Dictionary, market: Dictionary, slug: String, needed: float, tick: int) -> Dictionary:
    if str(pop.get("facility_location", "")) != str(market.get("facility_location", "")):
        return {"reason": "wrong_location"}
    var supply: Dictionary = market.get("supply", {})
    var prices: Dictionary = market.get("prices", {})
    var stock := float(supply.get(slug, 0.0))
    var price := float(prices.get(slug, 0.0))
    var cash := int(pop.get("total_wealth", 0))
    var seller := int(market.get("seller_credits", 0))
    if not is_finite(needed) or needed <= 0.0 or not is_finite(stock) or stock < 0.0 or not is_finite(price) or price <= 0.0:
        return {"reason": "invalid_quote"}
    if stock == 0.0:
        return {"reason": "insufficient_stock"}
    if cash <= 0:
        return {"reason": "insufficient_household_credits"}
    if seller < 0:
        return {"reason": "invalid_seller"}
    var qty := minf(needed, minf(stock, float(cash) / price))
    if qty <= 0.0:
        return {"reason": "insufficient_household_credits"}
    var payment_float := ceil(qty * price)
    # Never permit floating point rounding to overdraw the wallet.
    while payment_float > float(cash) and qty > 0.0:
        qty = qty * (1.0 - 0.0000001)
        payment_float = ceil(qty * price)
    if qty <= 0.0 or not is_finite(payment_float) or payment_float >= float(9223372036854775807) or payment_float > float(cash):
        return {"reason": "invalid_payment"}
    var payment := int(payment_float)
    if seller > 9223372036854775807 - payment:
        return {"reason": "credit_overflow"}
    # Single commit point after all validation; local market stock is consumed.
    pop["total_wealth"] = cash - payment
    market["seller_credits"] = seller + payment
    supply[slug] = maxf(0.0, stock - qty)
    market["supply"] = supply
    return {"quantity": qty, "payment": payment, "tick": tick, "reason": ""}

static func consume_cycle(pop: Dictionary, market: Dictionary, tick: int, tick_scale: float = 1.0, multiplier: int = 1) -> Array:
    var events: Array = []
    if multiplier <= 0 or tick < 0 or tick % (CONSUMPTION_INTERVAL_BASE * multiplier) != 0:
        return events
    var rates: Dictionary = pop.get("consumption", {})
    var needs: Dictionary = {}
    var count := maxi(0, int(pop.get("population_count", 0)))
    for slug in rates:
        var amount := float(rates[slug]) * float(count) / 1000.0
        if amount > 0.0:
            needs[str(slug)] = amount
    if int(pop.get("food_satisfaction", 50)) < EMERGENCY_WATER_THRESHOLD and count > 0:
        needs["water"] = float(needs.get("water", 0.0)) + EMERGENCY_WATER_RATE * float(count) / 1000.0
    var order: Array = needs.keys()
    order.sort_custom(func(a, b): return _priority(str(a)) < _priority(str(b)) if _priority(str(a)) != _priority(str(b)) else str(a) < str(b))
    var shortage := false
    for slug in order:
        var needed := float(needs[slug])
        var result := purchase(pop, market, str(slug), needed, tick)
        var qty := float(result.get("quantity", 0.0))
        if qty + 0.000001 < needed:
            shortage = true
        events.append({"kind": "population_purchase", "tick": tick, "population_id": pop.get("id", ""), "commodity": slug, "needed": needed, "quantity": qty, "payment": int(result.get("payment", 0)), "reason": result.get("reason", "")})
    var sat := int(pop.get("food_satisfaction", 50))
    sat = maxi(0, sat - FOOD_SAT_DROP_ON_SHORTAGE) if shortage else mini(100, sat + FOOD_SAT_RECOVER_ON_MET)
    pop["food_satisfaction"] = sat
    var target := (sat * 6 + int(pop.get("safety_satisfaction", 50)) * 2 + int(pop.get("entertainment_satisfaction", 50)) * 2) / 10
    var inertia := pow(SENTIMENT_INERTIA_BASE, maxf(tick_scale, 0.01))
    var overall := int(round(float(pop.get("overall_sentiment", 50)) * inertia + float(target) * (1.0 - inertia)))
    pop["overall_sentiment"] = overall
    pop["unrest"] = clampi(100 - overall, 0, 100)
    var delta := MIGRATION_PRESSURE_RISE * tick_scale if overall < MIGRATION_SENTIMENT_FLOOR else -MIGRATION_PRESSURE_DECAY * tick_scale
    pop["migration_pressure"] = clampf(float(pop.get("migration_pressure", 0.0)) + delta, 0.0, 2.0)
    return events

static func _priority(slug: String) -> int:
    if slug == "food":
        return 0
    if slug == "water":
        return 1
    return 2
