extends RefCounted
## N80. Pure considerations from frozen Rust ai/considerations.rs,
## and price freshness from agents/ship/mod.rs. Each returns {"axis", "value"}
## or {} for invalid/unavailable authority; never fabricate market knowledge.

const PRICE_MEMORY_HALF_LIFE_TICKS: float = 1500.0
const PRICE_MEMORY_FRESHNESS_FLOOR: float = 0.10
const AXIS_SAFETY: String = "safety"
const AXIS_PROFIT: String = "profit"
const AXIS_EXPLORATION: String = "exploration"

static func fuel_urgency(fuel: float, capacity: float) -> Dictionary:
    if not _finite(fuel) or not _finite(capacity) or capacity < 0.0:
        return {}
    # Frozen Rust ShipFuel::fraction(): zero-capacity => 0.0.
    # Do not mask missing propulsion as a full tank.
    var fraction: float = fuel / capacity if capacity > 0.0 else 0.0
    return _c(AXIS_SAFETY, 1.0 - fraction)

static func cargo_opportunity(cargo: Dictionary, capacity: int) -> Dictionary:
    var used: int = _cargo_used(cargo, capacity)
    if used < 0:
        return {}
    return _c(AXIS_PROFIT, float(maxi(capacity - used, 0)) / float(maxi(capacity, 1)))

static func cargo_to_sell(cargo: Dictionary, capacity: int) -> Dictionary:
    var used: int = _cargo_used(cargo, capacity)
    if used < 0:
        return {}
    return _c(AXIS_PROFIT, float(used) / float(maxi(capacity, 1)))

## Rust: 0 → 1, 1..499 → .8, 500..1999 → .4,
## 2000..9999 → .1, >=10000 → 0. Mapped to Safety.
static func financial_pressure(credits: int) -> Dictionary:
    var pressure: float = 0.0
    if credits <= 0:
        pressure = 1.0
    elif credits < 500:
        pressure = 0.8
    elif credits < 2000:
        pressure = 0.4
    elif credits < 10000:
        pressure = 0.1
    return _c(AXIS_SAFETY, pressure)

## Frozen Rust visited: Vec<String>, known-price markets: HashMap<String,..>.
## Neither is a physical navigation scan; uses only saved price memory.
static func exploration_desire(visited: Array, price_knowledge: Dictionary) -> Dictionary:
    if visited.is_empty() or price_knowledge.is_empty():
        return _c(AXIS_EXPLORATION, 0.3)
    var visited_map: Dictionary = {}
    for location in visited:
        visited_map[str(location)] = true
    var unvisited: int = 0
    for location in price_knowledge:
        if not visited_map.has(str(location)):
            unvisited += 1
    return _c(AXIS_EXPLORATION, float(unvisited) / float(price_knowledge.size()))

static func docked_at_facility(is_docked: bool) -> Dictionary:
    return _c(AXIS_SAFETY, 1.0 if is_docked else 0.0)

## The Rust saturating_sub() for ticks means an older current tick does
## not make future-observed prices more influential than 1.
static func price_freshness_weight(observed_tick: int, current_tick: int) -> float:
    if observed_tick < 0 or current_tick < 0:
        return -1.0
    var age: float = float(maxi(0, current_tick - observed_tick))
    return clampf(pow(2.0, -age / PRICE_MEMORY_HALF_LIFE_TICKS),
        PRICE_MEMORY_FRESHNESS_FLOOR, 1.0)

## Rust trade_opportunity: maximum cross-location, same-commodity
## price margin, lower price in denominator, scaled by MIN freshness
## and divided by 2.0 before clamp.
##
## Input: {location: {commodity: {"price": positive float,
##                                  "tick": nonnegative int}}}.
## Rust Typed PriceKnowledge is guaranteed valid; reject malformed
## GDScript snapshots rather than silently treating missing prices as zero.
static func trade_opportunity(price_knowledge: Dictionary,
        current_tick: int) -> Dictionary:
    if current_tick < 0:
        return {}
    var locations: Array = price_knowledge.keys()
    locations.sort()
    if locations.size() < 2:
        return _c(AXIS_PROFIT, 0.0)
    var best: float = 0.0
    for i in range(locations.size()):
        var a: Variant = price_knowledge[locations[i]]
        if not (a is Dictionary):
            return {}
        for j in range(i + 1, locations.size()):
            var b: Variant = price_knowledge[locations[j]]
            if not (b is Dictionary):
                return {}
            for commodity in a:
                if not b.has(commodity):
                    continue
                var pa: Variant = a[commodity]
                var pb: Variant = b[commodity]
                if not (pa is Dictionary) or not (pb is Dictionary):
                    return {}
                for record in [pa, pb]:
                    if not _finite(record.get("price", null)):
                        return {}
                    if not (record.get("tick", null) is int):
                        return {}
                    if int(record["tick"]) < 0:
                        return {}
                var low: float = minf(float(pa["price"]), float(pb["price"]))
                var high: float = maxf(float(pa["price"]), float(pb["price"]))
                var fresh: float = minf(price_freshness_weight(int(pa["tick"]), current_tick),
                    price_freshness_weight(int(pb["tick"]), current_tick))
                var margin: float = (high - low) / maxf(low, 1.0) * fresh
                best = maxf(best, margin)
    return _c(AXIS_PROFIT, best / 2.0)

static func _cargo_used(cargo: Dictionary, capacity: int) -> int:
    if capacity < 0:
        return -1
    var used: int = 0
    for key in cargo:
        var qty: Variant = cargo[key]
        if not (qty is int) or qty < 0 or qty > 4294967295:
            return -1
        if used > 4294967295 - int(qty):
            return -1
        used += int(qty)
    return used

static func _c(axis: String, value: float) -> Dictionary:
    return {"axis": axis, "value": clampf(value, 0.0, 1.0)}

static func _finite(value: Variant) -> bool:
    return (value is int or value is float) and is_finite(float(value))
