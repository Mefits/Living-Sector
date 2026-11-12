extends RefCounted
## N9: physical inventory boundaries for market/station commodity quantities.
## Rust economy/commodities.rs uses Cargo<Commodity,u32> for ships, while
## recipes.rs uses fractional HashMap<Commodity,f32> for market production.
## No invented universal capacity: caller supplies limits from actual entity data.
const Catalog = preload("res://scripts/sim/economy/commodity_catalog.gd")
const EPSILON := 0.000001

static func valid_amount(value: Variant) -> bool:
    if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
        return false
    return is_finite(float(value)) and float(value) >= 0.0

static func validate(stock: Dictionary, limits: Dictionary = {}) -> String:
    for key in stock:
        if typeof(key) != TYPE_STRING or not Catalog.contains(key):
            return "unknown commodity"
        if not valid_amount(stock[key]):
            return "invalid stock amount"
    for key in limits:
        if typeof(key) != TYPE_STRING or not Catalog.contains(key):
            return "unknown capacity commodity"
        if not valid_amount(limits[key]):
            return "invalid capacity"
        if float(stock.get(key, 0.0)) > float(limits[key]) + EPSILON:
            return "stock exceeds capacity"
    return ""

## Validate every leg before mutation. Return false without changing either
## dictionary if there is insufficient source stock or destination headroom.
## Separate ledgers are required: moving between identical dictionaries is invalid.
static func transfer(source: Dictionary, destination: Dictionary, quantities: Dictionary, source_limits: Dictionary = {}, destination_limits: Dictionary = {}) -> bool:
    if is_same(source, destination):
        return false
    if validate(source, source_limits) != "" or validate(destination, destination_limits) != "":
        return false
    if quantities.is_empty():
        return false
    var outgoing := source.duplicate(true)
    var incoming := destination.duplicate(true)
    for key in quantities:
        if typeof(key) != TYPE_STRING or not Catalog.contains(key):
            return false
        var quantity: Variant = quantities[key]
        if not valid_amount(quantity) or float(quantity) <= 0.0:
            return false
        var current_source := float(outgoing.get(key, 0.0))
        var current_destination := float(incoming.get(key, 0.0))
        var amount := float(quantity)
        if current_source < amount or not is_finite(current_destination + amount):
            return false
        outgoing[key] = current_source - amount
        incoming[key] = current_destination + amount
    if validate(outgoing, source_limits) != "" or validate(incoming, destination_limits) != "":
        return false
    # Mutate only after all legs pass. Caller must supply distinct inventories.
    source.clear()
    for key in outgoing:
        source[key] = outgoing[key]
    destination.clear()
    for key in incoming:
        destination[key] = incoming[key]
    return true

## Use this for integer-only ship holds. Market warehouses may use fractions.
static func validate_ship_hold(stock: Dictionary, max_total: int) -> String:
    if max_total < 0 or validate(stock) != "":
        return "invalid ship hold"
    var total := 0.0
    for key in stock:
        var amount := float(stock[key])
        if amount != floorf(amount):
            return "fractional ship cargo"
        total += amount
        if not is_finite(total):
            return "invalid cargo total"
    if total > float(max_total):
        return "cargo capacity exceeded"
    return ""

static func transfer_to_ship(source: Dictionary, hold: Dictionary, quantities: Dictionary, max_total: int) -> bool:
    if validate_ship_hold(hold, max_total) != "":
        return false
    var candidate := hold.duplicate(true)
    for key in quantities:
        if not valid_amount(quantities[key]) or float(quantities[key]) != floorf(float(quantities[key])):
            return false
        candidate[key] = float(candidate.get(key, 0.0)) + float(quantities[key])
    if validate_ship_hold(candidate, max_total) != "":
        return false
    return transfer(source, hold, quantities)

## Deterministic representation for save/checkpoint and equality tests.
static func canonical(stock: Dictionary) -> Array:
    if validate(stock) != "":
        return []
    var keys: Array = stock.keys()
    keys.sort()
    var result: Array = []
    for key in keys:
        result.append({"commodity": key, "quantity": float(stock[key])})
    return result
