extends RefCounted
## N97 — exclusive physical Apply from frozen Rust
## native/crates/sim_server/src/engine/transactions.rs.
## Receives a FULL AUTHORITATIVE SNAPSHOT; returns a detached changed copy
## ONLY if every check passes. The caller must NOT merge partial patches.
##
## world: {ships:{id:ship},facilities:{id:facility},
##         markets:{location:market},bodies:{body_id:body},
##         relations:{faction\u001ffaction:treaty},
##         market_controllers:{location:faction}}
## ship: {class,faction_id,location,docked_at,transit,
##        universe_offset:[x,y],credits,cargo_capacity,cargo,
##        cargo_age,cargo_origin,fuel,fuel_capacity,
##        crew_task,crew_skills,faction_reputation}
## facility: {location,faction_id,abandoned,credits,docked_ships,
##            reserves:{fuel:float}}
## market: {facility_id,location,prices,supply,trade_volume}
## body: {body_id,universe_offset,resources}
## NOTE: no factory tick, AI or UI, no separate funds minting.
const Market = preload("res://scripts/port/n97_ship_market_rules.gd")
const MAX_U32: int = 4294967295
const MAX_QUANTITY: int = 16777216  # 1 << 24
const MAX_MONEY: int = 9223372036854775807
const SAFE_FLOAT_MONEY: int = 9007199254740991
const SALVAGE_UNITS_PER_RICHNESS: float = 8000.0
const REFUEL_UNITS_PER_TICK: float = 2.0
const REFUEL_PRICE_PER_UNIT: int = 2

static func simulate(world: Dictionary, ship_id: String,
        request: Dictionary, tick: int) -> Dictionary:
    if tick < 0 or ship_id.is_empty():
        return _bad("invalid_apply_context")
    if not (world.get("ships", null) is Dictionary):
        return _bad("missing_ships_authority")
    if not (world["ships"].get(ship_id, null) is Dictionary):
        return _bad("missing_ship")
    var kind: String = str(request.get("kind", ""))
    if not ["buy", "sell", "mine", "refuel"].has(kind):
        return _bad("requires_other_rust_apply_module")
    # Staging by deep copying BEFORE writes. Rejecting never exposes it.
    var staged: Dictionary = world.duplicate(true)
    var ship: Dictionary = staged["ships"][ship_id]
    var result: Dictionary
    match kind:
        "buy":
            result = _buy(staged, ship, request, tick, ship_id)
        "sell":
            result = _sell(staged, ship, request, ship_id)
        "mine":
            result = _mine(staged, ship, request, tick)
        "refuel":
            result = _refuel(staged, ship, request)
        _:
            return _bad("unsupported_transaction_kind")
    if not bool(result.get("ok", false)):
        return result
    # These are the ONLY source-backed committed mutations in this slice.
    # The external exclusive event executor handles acknowledgements.
    return {
        "ok": true, "world": staged,
        "quantity": float(result["quantity"]),
        "payment": int(result["payment"]),
        "transaction": kind
    }

static func _check_dock(world: Dictionary, ship: Dictionary,
        location: String) -> Dictionary:
    if location.is_empty() or str(ship.get("location", "")) != location:
        return _bad("wrong_location")
    if not (ship.get("transit", null) is Dictionary):
        return _bad("missing_transit")
    if not (ship["transit"] as Dictionary).is_empty():
        return _bad("wrong_location")
    var dock_id: Variant = ship.get("docked_at", null)
    if not (dock_id is String) or dock_id.is_empty():
        return _bad("not_docked")
    if not (world.get("facilities", null) is Dictionary):
        return _bad("missing_facilities")
    if not (world["facilities"].get(dock_id, null) is Dictionary):
        return _bad("missing_dock")
    var facility: Dictionary = world["facilities"][dock_id]
    if str(facility.get("location", "")) != location:
        return _bad("invalid_dock")
    if not (facility.get("docked_ships", null) is Array):
        return _bad("missing_dock_storage")
    if not (facility["docked_ships"] as Array).has(str(ship.get("id", ""))):
        return _bad("invalid_dock")
    if bool(facility.get("abandoned", false)):
        return _bad("invalid_dock")
    if not (world.get("relations", null) is Dictionary):
        return _bad("missing_relations")
    var allowed: Dictionary = Market.commerce_allowed(world["relations"],
        str(ship.get("faction_id", "")), str(facility.get("faction_id", "")))
    if not bool(allowed.get("ok", false)):
        return allowed
    if not bool(allowed["allowed"]):
        return _bad("embargo")
    return {"ok": true, "facility_id": str(dock_id)}

static func _controller(world: Dictionary, ship: Dictionary,
        location: String) -> Dictionary:
    if not (world.get("market_controllers", null) is Dictionary):
        return _bad("missing_market_controllers")
    if not (world.get("relations", null) is Dictionary):
        return _bad("missing_relations")
    var owner: String = str(world["market_controllers"].get(location, ""))
    var allowed: Dictionary = Market.commerce_allowed(world["relations"],
        str(ship.get("faction_id", "")), owner)
    if not bool(allowed.get("ok", false)):
        return allowed
    if not bool(allowed["allowed"]):
        return _bad("embargo")
    return {"ok": true, "owner": owner}

static func _market(world: Dictionary, ship: Dictionary,
        location: String) -> Dictionary:
    if not (world.get("markets", null) is Dictionary):
        return _bad("missing_markets")
    if not (world["markets"].get(location, null) is Dictionary):
        return _bad("missing_market")
    var market: Dictionary = world["markets"][location]
    var seller_id: String = str(market.get("facility_id", ""))
    if seller_id.is_empty():
        return _bad("missing_market_owner")
    if not (world.get("facilities", null) is Dictionary) or not (world["facilities"].get(seller_id, null) is Dictionary):
        return _bad("missing_seller")
    var seller: Dictionary = world["facilities"][seller_id]
    var allowed: Dictionary = Market.commerce_allowed(world["relations"],
        str(ship.get("faction_id", "")), str(seller.get("faction_id", "")))
    if not bool(allowed.get("ok", false)):
        return allowed
    if not bool(allowed["allowed"]):
        return _bad("embargo")
    if bool(seller.get("abandoned", false)):
        return _bad("seller_abandoned")
    if str(market.get("location", "")) != location or str(seller.get("location", "")) != location:
        return _bad("wrong_market_location")
    return {"ok": true, "market": market, "seller": seller,
        "seller_id": seller_id}

static func _quote(world: Dictionary, ship: Dictionary,
        location: String, market: Dictionary, commodity: String) -> Dictionary:
    var base: Dictionary = Market.price_for(market, commodity)
    if not bool(base.get("ok", false)):
        return base
    var owner: Dictionary = _controller(world, ship, location)
    if not bool(owner.get("ok", false)):
        return owner
    if not (ship.get("faction_reputation", null) is Dictionary):
        return _bad("missing_faction_reputation")
    var rep: Variant = (ship["faction_reputation"] as Dictionary).get(owner["owner"], 0)
    if typeof(rep) != TYPE_INT:
        return _bad("invalid_reputation")
    var posture: Dictionary = Market.posture(world["relations"],
        str(ship.get("faction_id", "")), str(owner["owner"]), int(rep))
    if not bool(posture.get("ok", false)):
        return posture
    var price: float = float(base["price"]) * float(posture["multiplier"])
    if not is_finite(price):
        return _bad("invalid_or_changed_price")
    return {"ok": true, "price": price}

static func _physical_cargo(ship: Dictionary) -> Dictionary:
    var capacity: Variant = ship.get("cargo_capacity", null)
    var cargo_value: Variant = ship.get("cargo", null)
    if typeof(capacity) != TYPE_INT or int(capacity) < 0 or int(capacity) > MAX_U32:
        return _bad("invalid_cargo_capacity")
    if not (cargo_value is Dictionary):
        return _bad("missing_cargo")
    var total: int = 0
    for good in cargo_value:
        var quantity: Variant = cargo_value[good]
        if not Market.BASE_PRICE.has(str(good)) or typeof(quantity) != TYPE_INT:
            return _bad("invalid_cargo_entry")
        if int(quantity) < 0 or int(quantity) > MAX_U32 or total > MAX_U32 - int(quantity):
            return _bad("cargo_overflow")
        total += int(quantity)
    if total > int(capacity):
        return _bad("cargo_exceeds_capacity")
    return {"ok": true, "used": total, "free": int(capacity) - total}

static func _buy(world: Dictionary, ship: Dictionary, request: Dictionary,
        tick: int, ship_id: String) -> Dictionary:
    var at: String = str(request.get("location", ""))
    var commodity: String = str(request.get("commodity", ""))
    var wanted: Variant = request.get("quantity", null)
    var limit: Variant = request.get("max_unit_price", null)
    if not _amount(wanted) or not Market.BASE_PRICE.has(commodity) or not _finite(limit):
        return _bad("invalid_buy_request")
    var dock: Dictionary = _check_dock(world, ship, at)
    if not bool(dock.get("ok", false)):
        return dock
    var market_data: Dictionary = _market(world, ship, at)
    if not bool(market_data.get("ok", false)):
        return market_data
    var market: Dictionary = market_data["market"]
    var seller: Dictionary = market_data["seller"]
    var quote: Dictionary = _quote(world, ship, at, market, commodity)
    if not bool(quote.get("ok", false)):
        return quote
    var price: float = float(quote["price"])
    if price <= 0.0 or price > float(limit):
        return _bad("invalid_or_changed_price")
    var stock: Dictionary = Market.supply(market, commodity)
    if not bool(stock.get("ok", false)):
        return stock
    if int(wanted) <= 0 or int(wanted) > MAX_QUANTITY or float(stock["quantity"]) < float(wanted):
        return _bad("insufficient_stock")
    var capacity: Dictionary = _physical_cargo(ship)
    if not bool(capacity.get("ok", false)):
        return capacity
    if int(capacity["free"]) < int(wanted):
        return _bad("insufficient_capacity")
    var ship_cash: Variant = ship.get("credits", null)
    var seller_cash: Variant = seller.get("credits", null)
    if not _cash(ship_cash) or not _cash(seller_cash):
        return _bad("invalid_credit_state")
    # Rust uses ceil(price f64 * qty) after a f32 market quote.
    # Our f64 GDScript calculation uses source-roundtrippable floats;
    # reject money above exact f64 integer range instead of rounding.
    var value: float = ceil(price * float(wanted))
    if not is_finite(value) or value >= float(MAX_MONEY) or value > float(ship_cash) or value > float(SAFE_FLOAT_MONEY):
        return _bad("insufficient_credits")
    var cost: int = int(value)
    if int(ship_cash) < cost:
        return _bad("insufficient_credits")
    if int(seller_cash) > MAX_MONEY - cost:
        return _bad("credit_overflow")
    if not (ship.get("cargo_age", null) is Dictionary) or not (ship.get("cargo_origin", null) is Dictionary):
        return _bad("missing_cargo_provenance")
    if not (market.get("supply", null) is Dictionary):
        return _bad("missing_market_supply")
    # All source checks passed. Mutate only staged detached world.
    market["supply"][commodity] = float(stock["quantity"]) - float(wanted)
    ship["credits"] = int(ship_cash) - cost
    seller["credits"] = int(seller_cash) + cost
    seller["dirty"] = true
    ship["cargo"][commodity] = int(ship["cargo"].get(commodity, 0)) + int(wanted)
    ship["cargo_age"][commodity] = tick
    ship["cargo_origin"][commodity] = {"location": at,
        "unit_cost": float(cost) / float(wanted)}
    _crew_success(ship, "loading", false)
    _dirty_market(market)
    return {"ok": true, "quantity": float(wanted), "payment": cost}

## Frozen Rust binary-search partial fill: never borrow from a market.
static func affordable_sale_quantity(quantity: int, price: float, credits: int) -> int:
    if quantity <= 0 or credits <= 0 or not is_finite(price) or price <= 0.0:
        return 0
    var low: int = 0
    var high: int = quantity
    while low < high:
        var middle: int = low + (high - low + 1) / 2
        var pay: float = floor(price * float(middle))
        if pay >= 1.0 and pay < float(MAX_MONEY) and pay <= float(credits):
            low = middle
        else:
            high = middle - 1
    return low

static func _sell(world: Dictionary, ship: Dictionary, request: Dictionary,
        ship_id: String) -> Dictionary:
    var at: String = str(request.get("location", ""))
    var commodity: String = str(request.get("commodity", ""))
    var quantity: Variant = request.get("quantity", null)
    var min_price: Variant = request.get("min_unit_price", null)
    if not _amount(quantity) or not Market.BASE_PRICE.has(commodity) or not _finite(min_price):
        return _bad("invalid_sell_request")
    var dock: Dictionary = _check_dock(world, ship, at)
    if not bool(dock.get("ok", false)):
        return dock
    var market_data: Dictionary = _market(world, ship, at)
    if not bool(market_data.get("ok", false)):
        return market_data
    var market: Dictionary = market_data["market"]
    var buyer: Dictionary = market_data["seller"]
    var quote: Dictionary = _quote(world, ship, at, market, commodity)
    if not bool(quote.get("ok", false)):
        return quote
    var price: float = float(quote["price"])
    if price <= 0.0 or float(min_price) <= 0.0 or price < float(min_price):
        return _bad("invalid_or_changed_price")
    var current_stock: Dictionary = Market.supply(market, commodity)
    if not bool(current_stock.get("ok", false)):
        return current_stock
    var stock: float = float(current_stock["quantity"])
    var physical: Dictionary = _physical_cargo(ship)
    if not bool(physical.get("ok", false)):
        return physical
    var have: int = int(ship["cargo"].get(commodity, 0))
    if int(quantity) <= 0 or int(quantity) > MAX_QUANTITY or have < int(quantity):
        return _bad("insufficient_cargo")
    var buyer_cash: Variant = buyer.get("credits", null)
    var ship_cash: Variant = ship.get("credits", null)
    if not _cash(buyer_cash) or not _cash(ship_cash):
        return _bad("invalid_credit_state")
    var sold: int = affordable_sale_quantity(int(quantity), price, int(buyer_cash))
    if sold <= 0:
        return _bad("insufficient_buyer_credits")
    var after: float = stock + float(sold)
    var delta: float = absf(after - stock - float(sold))
    var tolerance: float = maxf(float(sold) * 0.00001, 0.001)
    if stock < 0.0 or not is_finite(after) or after <= stock or delta > tolerance:
        return _bad("invalid_destination_stock")
    var value: float = floor(price * float(sold))
    if value < 1.0 or value >= float(MAX_MONEY) or value > float(SAFE_FLOAT_MONEY):
        return _bad("invalid_payment")
    var payment: int = int(value)
    if int(buyer_cash) < payment:
        return _bad("insufficient_buyer_credits")
    if int(ship_cash) > MAX_MONEY - payment:
        return _bad("credit_overflow")
    if not (ship.get("cargo_age", null) is Dictionary) or not (ship.get("cargo_origin", null) is Dictionary):
        return _bad("missing_cargo_provenance")
    var origin: Variant = ship["cargo_origin"].get(commodity, null)
    # All fallible checks above. Actual seller ship balance increases,
    # actual market facility balance decreases: no fictional buyer.
    ship["credits"] = int(ship_cash) + payment
    buyer["credits"] = int(buyer_cash) - payment
    buyer["dirty"] = true
    market["supply"][commodity] = after
    if have == sold:
        ship["cargo"].erase(commodity)
        ship["cargo_age"].erase(commodity)
        ship["cargo_origin"].erase(commodity)
        if origin is Dictionary and str(origin.get("location", "")) != at:
            # Rust stores route_performance only when entire stack sold
            # and origin differs from current location.
            var route_name: String = str(origin.get("location", "")) + "\u001f" + at + "\u001f" + commodity
            if not (ship.get("route_performance", null) is Dictionary):
                return _bad("missing_route_performance_authority")
            # Actual route mean/count statistic updates need real
            # route snapshot. Never fabricate from missing fields.
            if not _finite(origin.get("unit_cost", null)):
                return _bad("invalid_cargo_origin")
            var entry: Dictionary = (ship["route_performance"] as Dictionary).get(
                route_name, {"attempts": 0, "total_profit_per_unit": 0.0})
            if typeof(entry.get("attempts", null)) != TYPE_INT or not _finite(entry.get("total_profit_per_unit", null)):
                return _bad("invalid_route_performance")
            entry["attempts"] = mini(MAX_U32, int(entry["attempts"]) + 1)
            entry["total_profit_per_unit"] = float(entry["total_profit_per_unit"]) + float(payment) / float(sold) - float(origin["unit_cost"])
            ship["route_performance"][route_name] = entry
    else:
        ship["cargo"][commodity] = have - sold
    if not (market.get("trade_volume", null) is Dictionary):
        return _bad("missing_market_history")
    market["trade_volume"][commodity] = float(market["trade_volume"].get(commodity, 0.0)) + float(sold)
    _crew_success(ship, "unloading", false)
    _dirty_market(market)
    return {"ok": true, "quantity": float(sold), "payment": payment}

static func _mine(world: Dictionary, ship: Dictionary,
        request: Dictionary, tick: int) -> Dictionary:
    if str(ship.get("class", "")) != "miner":
        return _bad("requires_miner")
    if str(request.get("commodity", "")) != "ice":
        return _bad("unsupported_mining_commodity")
    var wanted: Variant = request.get("quantity", null)
    if typeof(wanted) != TYPE_INT or int(wanted) < 1 or int(wanted) > 40:
        return _bad("invalid_mining_quantity")
    var body_id: String = str(request.get("body_id", ""))
    var location: String = str(request.get("location", ""))
    if location.is_empty() or location != "mine-" + body_id:
        return _bad("not_a_mining_waypoint")
    if location != str(ship.get("location", "")) or ship.get("docked_at", null) != null:
        return _bad("wrong_mining_location")
    if not (ship.get("transit", null) is Dictionary) or not (ship["transit"] as Dictionary).is_empty():
        return _bad("wrong_mining_location")
    if not (world.get("bodies", null) is Dictionary) or not (world["bodies"].get(body_id, null) is Dictionary):
        return _bad("missing_mining_body")
    var body: Dictionary = world["bodies"][body_id]
    if str(body.get("body_id", "")) != body_id:
        return _bad("mismatched_mining_body")
    if not (ship.get("universe_offset", null) is Array) or not (body.get("universe_offset", null) is Array):
        return _bad("missing_body_orbit")
    if (ship["universe_offset"] as Array) != (body["universe_offset"] as Array):
        return _bad("mining_other_system")
    if not (body.get("resources", null) is Dictionary):
        return _bad("missing_body_resources")
    var richness: Variant = body["resources"].get("ice", 0.0)
    if not _finite(richness) or float(richness) < 0.0 or float(richness) > 1.0:
        return _bad("invalid_body_resource")
    var physical: Dictionary = _physical_cargo(ship)
    if not bool(physical.get("ok", false)):
        return physical
    var available: int = int(floor(float(richness) * SALVAGE_UNITS_PER_RICHNESS))
    var extracted: int = mini(int(wanted), mini(int(physical["free"]), available))
    if extracted <= 0:
        return _bad("exhausted_deposit_or_full_hold")
    if not (ship.get("cargo_age", null) is Dictionary):
        return _bad("missing_cargo_provenance")
    body["resources"]["ice"] = maxf(0.0, float(richness) - float(extracted) / SALVAGE_UNITS_PER_RICHNESS)
    ship["cargo"]["ice"] = int(ship["cargo"].get("ice", 0)) + extracted
    if not ship["cargo_age"].has("ice"):
        ship["cargo_age"]["ice"] = tick
    ship["crew_task"] = "engineering"
    _grant_skill(ship, "engineering", 1)
    return {"ok": true, "quantity": float(extracted), "payment": 0}

static func _refuel(world: Dictionary, ship: Dictionary,
        request: Dictionary) -> Dictionary:
    var location: String = str(request.get("location", ""))
    var dock: Dictionary = _check_dock(world, ship, location)
    if not bool(dock.get("ok", false)):
        return dock
    var owner: Dictionary = _controller(world, ship, location)
    if not bool(owner.get("ok", false)):
        return owner
    var facility: Dictionary = world["facilities"][dock["facility_id"]]
    var fuel: Variant = ship.get("fuel", null)
    var capacity: Variant = ship.get("fuel_capacity", null)
    if not _finite(fuel) or not _finite(capacity):
        return _bad("invalid_fuel_state")
    if float(fuel) < 0.0 or float(capacity) <= 0.0 or float(fuel) > float(capacity):
        return _bad("invalid_fuel_state")
    if not (facility.get("reserves", null) is Dictionary):
        return _bad("missing_dock_storage")
    var reserves: Variant = facility["reserves"].get("fuel", 0.0)
    if not _finite(reserves) or float(reserves) < 0.0:
        return _bad("invalid_fuel_state")
    var market_quantity: float = 0.0
    var backed_market: Dictionary = _market(world, ship, location)
    var is_backed: bool = bool(backed_market.get("ok", false)) and str(backed_market.get("seller_id", "")) == str(dock["facility_id"])
    if is_backed:
        var stock: Dictionary = Market.supply(backed_market["market"], "fuel")
        if not bool(stock.get("ok", false)):
            return stock
        market_quantity = float(stock["quantity"])
    if market_quantity < 0.0:
        return _bad("invalid_fuel_state")
    var amount: float = minf(REFUEL_UNITS_PER_TICK,
        minf(float(capacity) - float(fuel), float(reserves) + market_quantity))
    if amount <= 0.0:
        return _bad("no_fuel_transfer")
    var from_reserve: float = minf(amount, float(reserves))
    var from_market: float = amount - from_reserve
    var payment: int = int(ceil(amount)) * REFUEL_PRICE_PER_UNIT
    var cash: Variant = ship.get("credits", null)
    var seller_cash: Variant = facility.get("credits", null)
    if not _cash(cash) or not _cash(seller_cash):
        return _bad("invalid_credit_state")
    if int(cash) < payment:
        return _bad("insufficient_credits")
    if int(seller_cash) > MAX_MONEY - payment:
        return _bad("credit_overflow")
    ship["fuel"] = float(fuel) + amount
    ship["credits"] = int(cash) - payment
    facility["reserves"]["fuel"] = float(reserves) - from_reserve
    if from_market > 0.0 and is_backed:
        backed_market["market"]["supply"]["fuel"] = market_quantity - from_market
        _dirty_market(backed_market["market"])
    facility["credits"] = int(seller_cash) + payment
    facility["dirty"] = true
    return {"ok": true, "quantity": amount, "payment": payment}

static func _crew_success(ship: Dictionary, task: String,
        navigation: bool) -> void:
    if ship.has("crew_task"):
        ship["crew_task"] = task
    _grant_skill(ship, "trading", 1)
    if navigation:
        _grant_skill(ship, "navigation", 1)

static func _grant_skill(ship: Dictionary, name: String, amount: int) -> void:
    if not (ship.get("crew_skills", null) is Dictionary):
        return
    var skills: Dictionary = ship["crew_skills"]
    var prior: int = int(skills.get(name, 0))
    skills[name] = mini(100, prior + amount)

static func _dirty_market(market: Dictionary) -> void:
    market["dirty"] = true

static func _cash(value: Variant) -> bool:
    return typeof(value) == TYPE_INT and int(value) >= 0

static func _amount(value: Variant) -> bool:
    return typeof(value) == TYPE_INT and int(value) >= 0 and int(value) <= MAX_U32

static func _finite(value: Variant) -> bool:
    return (value is int or value is float) and is_finite(float(value))

static func _bad(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
