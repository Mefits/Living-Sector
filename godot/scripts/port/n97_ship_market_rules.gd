extends RefCounted
## N97 frozen Rust economy/commodities.rs, agents/faction_relations.rs
## and agents/market.rs. Read-only market/diplomatic predicates for
## exclusive ShipTransaction Apply (never accept a caller-provided price).
const BASE_PRICE = {
    "ore": 15.0, "ice": 10.0, "gas": 20.0,
    "rare_ore": 75.0, "crystal_ore": 140.0,
    "metals": 45.0, "fuel": 25.0, "polymers": 40.0,
    "water": 12.0, "alloys": 145.0,
    "components": 80.0, "electronics": 120.0,
    "quantum_cores": 320.0, "tools": 90.0,
    "food": 18.0, "medical": 100.0, "luxury": 150.0
}
const TREATIES = ["neutral", "trade_pact", "allied", "tense", "hostile", "war"]

## Snapshot input relations uses explicitly supplied treaty names (the
## relation lookup defaults to Neutral in frozen Rust). Treat pair as
## unordered just like FactionRelations::state_or_default. Contradictory
## directions fail closed: a caller must first normalize its authority.
static func treaty(relations: Dictionary, faction: String, owner: String) -> Dictionary:
    if faction.is_empty() or owner.is_empty() or faction == owner:
        return {"ok": true, "treaty": "neutral"}
    var forward: String = faction + "\u001f" + owner
    var reverse: String = owner + "\u001f" + faction
    var a: Variant = relations.get(forward, "neutral")
    var b: Variant = relations.get(reverse, a)
    if not (a is String) or not (b is String):
        return {"ok": false, "reason": "invalid_treaty_source"}
    if not TREATIES.has(a) or not TREATIES.has(b):
        return {"ok": false, "reason": "invalid_treaty_kind"}
    if relations.has(forward) and relations.has(reverse) and a != b:
        return {"ok": false, "reason": "ambiguous_treaty_direction"}
    return {"ok": true, "treaty": str(a if relations.has(forward) else b)}

static func commerce_allowed(relations: Dictionary,
        ship_faction: String, market_faction: String) -> Dictionary:
    var relation: Dictionary = treaty(relations, ship_faction, market_faction)
    if not bool(relation.get("ok", false)):
        return relation
    return {"ok": true, "allowed": not ["hostile", "war"].has(relation["treaty"])}

## market_buy_multiplier is intentionally applied for BUY and SELL.
## The separate Rust market_sell_multiplier reciprocal must NOT be used
## here (it caused free same-port arbitrage before being corrected).
static func posture(relations: Dictionary, faction: String, controller: String,
        rep: int) -> Dictionary:
    if rep < 0 or rep > 100:
        return {"ok": false, "reason": "invalid_reputation"}
    var relation: Dictionary = treaty(relations, faction, controller)
    if not bool(relation.get("ok", false)):
        return relation
    var effective: int = 50 if controller.is_empty() else (
        100 if not faction.is_empty() and faction == controller else rep
    )
    var base: float = clampf(1.0 + (50.0 - float(effective)) * 0.005, 0.75, 1.25)
    if ["hostile", "war"].has(relation["treaty"]) and base > 1.0:
        return {"ok": true, "multiplier": 1.0 + (base - 1.0) * 2.0}
    return {"ok": true, "multiplier": base}

static func price_for(market: Dictionary, commodity: String) -> Dictionary:
    if not BASE_PRICE.has(commodity):
        return {"ok": false, "reason": "unknown_commodity"}
    var prices: Variant = market.get("prices", null)
    if not (prices is Dictionary):
        return {"ok": false, "reason": "missing_pricing"}
    var candidate: Variant = prices.get(commodity, BASE_PRICE[commodity])
    if not (candidate is int or candidate is float) or not is_finite(float(candidate)):
        return {"ok": false, "reason": "invalid_price"}
    return {"ok": true, "price": float(candidate)}

## We accept Rust nonnegative market quantities as f32, not fake integer
## stock. Negative/nonfinite values are rejected before any mutation.
static func supply(market: Dictionary, commodity: String) -> Dictionary:
    var supplies: Variant = market.get("supply", null)
    if not (supplies is Dictionary):
        return {"ok": false, "reason": "missing_market_supply"}
    var value: Variant = supplies.get(commodity, 0.0)
    if not (value is int or value is float) or not is_finite(float(value)):
        return {"ok": false, "reason": "invalid_market_supply"}
    return {"ok": true, "quantity": float(value)}
