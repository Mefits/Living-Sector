extends RefCounted
## P2 N153 autonomous contract choice against ONE N39/N104 world snapshot.
## Source N153 does the actual profitability/cargo/commerce/sensor gating.
## This adapter only supplies verifiable N104/N150/N9/route observations.
## NO fake treaties, ship sensors, market knowledge, fuel or contract success.
const N153 = preload("res://scripts/sim/phase1/n153_native_ship_contract_selection.gd")
const Catalog = preload("res://scripts/sim/ship_catalog.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")
const Transit = preload("res://scripts/sim/ship_transit.gd")

static func _ready_ship(world: Dictionary, ship_id: String, contract: Dictionary,
        graph: RefCounted, positions: Dictionary, resolver: RefCounted,
        tick_scale: float) -> Dictionary:
    var ship: Dictionary = world["ships"][ship_id]
    if str(ship.get("active_contract_id", "")) != "" or not (ship.get("transit", {}) as Dictionary).is_empty():
        return {"ok": false, "reason": "ship_busy"}
    if str(ship.get("docked_at", "")) != "" or str(ship.get("location", "")) == "":
        return {"ok": false, "reason": "ship_docked_or_in_transit"}
    if not (ship.get("cargo") is Dictionary) or not ship["cargo"].is_empty():
        return {"ok": false, "reason": "ship_cargo_not_empty"}
    var quantity: int = int(contract.get("quantity", 0))
    if quantity < 1 or int(ship.get("cargo_capacity", 0)) < quantity:
        return {"ok": false, "reason": "cargo_capacity"}
    var source: String = str(contract.get("source_location", ""))
    var dest: String = str(contract.get("destination_location", ""))
    var here: String = str(ship.get("location", ""))
    if not graph.has_location(source) or not graph.has_location(dest) or not graph.has_location(here):
        return {"ok": false, "reason": "native_route_endpoint_unmapped"}
    var inbound: Dictionary = graph.shortest_path(here, source)
    var outbound: Dictionary = graph.shortest_path(source, dest)
    if not inbound.get("reachable", false) or not outbound.get("reachable", false):
        return {"ok": false, "reason": "unreachable_directed_route"}
    if not positions.has(here) or not positions.has(source) or not positions.has(dest):
        return {"ok": false, "reason": "missing_real_world_position"}
    var spec: Dictionary = Catalog.spec(str(ship.get("class", "")))
    var speed: float = Catalog.effective_speed(str(ship.get("class", "")), str(ship.get("size", "")))
    var rate: float = float(spec.get("fuel_consumption_base", 0.0))
    if speed <= 0.0 or rate <= 0.0 or float(ship.get("fuel", 0.0)) <= 0.0:
        return {"ok": false, "reason": "invalid_fuel_or_class"}
    # N14 advances one physical directed edge per tick. Check the COMPLETE
    # source+destination trip from real moving world positions before an AI
    # accepts an obligation; otherwise we could strand a ship with cargo.
    var flight_cost: float = 0.0
    for path in [inbound["locations"], outbound["locations"]]:
        for i in range(1, path.size()):
            var from_id: String = str(path[i - 1])
            var to_id: String = str(path[i])
            if not positions.has(from_id) or not positions.has(to_id):
                return {"ok": false, "reason": "missing_leg_world_position"}
            var a: Vector2 = positions[from_id]
            var b: Vector2 = positions[to_id]
            var distance: float = a.distance_to(b)
            var velocity: float = Transit.BASE_VELOCITY * speed * tick_scale
            if velocity <= 0.0 or not is_finite(distance) or distance <= 0.0:
                return {"ok": false, "reason": "invalid_flight_geometry"}
            flight_cost += float(maxi(1, ceili(distance / velocity))) * rate * tick_scale
    if float(ship["fuel"]) + 0.0001 < flight_cost:
        return {"ok": false, "reason": "insufficient_native_full_route_fuel"}
    return {"ok": true, "path_to_source": inbound["locations"],
        "source_to_destination": outbound["locations"]}

static func propose(world: Dictionary, graph: RefCounted,
        positions: Dictionary, resolver: RefCounted, tick: int,
        tick_scale: float, factions: Dictionary = {}) -> Dictionary:
    if tick < 0 or graph == null or resolver == null or tick_scale <= 0.0 or not is_finite(tick_scale):
        return {"ok": false, "reason": "unavailable_native_ai_context"}
    if not (world.get("ships") is Dictionary) or not (world.get("contract_board") is Dictionary):
        return {"ok": false, "reason": "missing_canonical_contracts_or_fleet"}
    var contracts: Dictionary = world["contract_board"].get("contracts", {})
    if not (world.get("markets") is Dictionary) or not (world.get("facilities") is Dictionary):
        return {"ok": false, "reason": "missing_actual_markets"}
    var ships: Array = world["ships"].keys()
    ships.sort()
    var ids: Array = contracts.keys()
    ids.sort()
    var candidates: Array = []
    var blocked: Array = []
    var already_assigned: Dictionary = {}
    for contract_id in ids:
        var c: Dictionary = contracts[contract_id]
        if str(c.get("status", "")) != "posted" or str(c.get("contract_type", "")) != "delivery":
            continue
        if tick > int(c.get("expires_at_tick", -1)):
            blocked.append({"contract_id": str(contract_id), "reason": "offer_expired"})
            continue
        var source: String = str(c.get("source_location", ""))
        var dest: String = str(c.get("destination_location", ""))
        if not world["markets"].has(source) or not world["markets"].has(dest):
            blocked.append({"contract_id": str(contract_id), "reason": "market_missing"})
            continue
        var seller_market: Dictionary = world["markets"][source]
        var buyer_market: Dictionary = world["markets"][dest]
        if not world["facilities"].has(str(seller_market.get("owner", ""))) or not world["facilities"].has(str(buyer_market.get("owner", ""))):
            blocked.append({"contract_id": str(contract_id), "reason": "source_owner_missing"})
            continue
        var seller: Dictionary = world["facilities"][str(seller_market["owner"])]
        var buyer: Dictionary = world["facilities"][str(buyer_market["owner"])]
        var good: String = str(c.get("commodity", ""))
        var qty: int = int(c.get("quantity", 0))
        var stock: float = float(seller_market.get("supply", {}).get(good, 0.0))
        if not is_finite(stock) or stock < float(qty):
            blocked.append({"contract_id": str(contract_id), "reason": "source_stock_unavailable"})
            continue
        # In the frozen source N135 missing treaties default Neutral; only
        # matching faction is provable without a live FactionRelations bridge.
        # Unknown cross-faction commerce must fail closed until that bridge.
        var buyer_faction: String = str(buyer.get("faction", ""))
        var seller_faction: String = str(seller.get("faction", ""))
        if buyer_faction != seller_faction or not factions.has(buyer_faction):
            blocked.append({"contract_id": str(contract_id), "reason": "faction_relations_not_integrated"})
            continue
        var source_price: Variant = seller_market.get("prices", {}).get(good, null)
        if not (source_price is int or source_price is float) or not is_finite(float(source_price)) or float(source_price) <= 0.0:
            blocked.append({"contract_id": str(contract_id), "reason": "missing_source_quote"})
            continue
        var source_purchase: int = int(ceil(float(qty) * float(source_price)))
        var winner: Dictionary = {}
        for ship_id in ships:
            var ship: Dictionary = world["ships"][ship_id]
            if str(ship.get("faction_id", "")) != buyer_faction or already_assigned.has(str(ship_id)):
                continue
            var readiness: Dictionary = _ready_ship(world, str(ship_id), c, graph, positions, resolver, tick_scale)
            if not readiness.get("ok", false):
                continue
            var here: String = str(ship["location"])
            # Source-market quote is genuinely available ONLY to ships at
            # that market. No fabricated omniscient price_knowledge in AI.
            var observations: Dictionary = {}
            # N80 persists a ship's genuinely observed market knowledge.
            # We never silently copy every world market into every ship.
            if ship.get("price_knowledge") is Dictionary:
                observations = ship["price_knowledge"].duplicate(true)
            if here == source:
                observations[source] = {}
                observations[source][good] = {"price": float(source_price)}
            var systems: Dictionary = {}
            systems[here] = resolver.system_for_location(here)
            systems[source] = resolver.system_for_location(source)
            systems[dest] = resolver.system_for_location(dest)
            if systems.values().has(""):
                continue
            var sensor: Variant = ship.get("sensor_range_au", null)
            if not (sensor is int or sensor is float) or not is_finite(float(sensor)) or float(sensor) < 0.0:
                sensor = 0.0 # Unknown sensor is never invented as long-range.
            var offer: Dictionary = {
                "id": str(contract_id), "status": "Posted", "contract_type": "Delivery",
                "faction_id": buyer_faction, "requestor_id": str(c.get("requestor_id", "")),
                "source_location": source, "destination_location": dest,
                "commodity": good, "quantity": qty, "may_accept": true}
            var controllers: Dictionary = {}
            controllers[source] = seller_faction
            controllers[dest] = buyer_faction
            var quotes: Dictionary = {}
            quotes[str(contract_id)] = {"valid": true,
                "quoted_payment": int(c["payment"]), "top_up": 0,
                "payer_balance": int(buyer["credits"]),
                "reserved": int(c["reserved"]), "source_purchase_cost": source_purchase}
            var commerce: Dictionary = {}
            commerce[buyer_faction] = true
            var context: Dictionary = {
                "offers": [offer], "ship_id": str(ship_id),
                "ship_faction": str(ship["faction_id"]), "ship_location": here,
                "cargo_capacity": int(ship["cargo_capacity"]), "credits": int(ship.get("credits", 0)),
                "sensor_range_au": float(sensor), "system_by_location": systems,
                "controllers": controllers,
                "commerce_allowed": commerce,
                "quotes": quotes,
                "memory": {"price_knowledge": observations},
                "tick": tick}
            var choice: Dictionary = N153.select_contract(context)
            if str(choice.get("id", "")) == str(contract_id):
                var row: Dictionary = {"contract_id": str(contract_id), "ship_id": str(ship_id),
                    "profit": int(choice["profit"]), "source": source,
                    "destination": dest, "path_to_source": readiness["path_to_source"],
                    "path_to_destination": readiness["source_to_destination"],
                    "source_purchase_cost": source_purchase}
                if winner.is_empty() or int(row["profit"]) > int(winner["profit"]):
                    winner = row
        if winner.is_empty():
            blocked.append({"contract_id": str(contract_id), "reason": "n153_no_eligible_profitable_known_ship"})
            continue
        candidates.append(winner)
        already_assigned[str(winner["ship_id"])] = true
    return {"ok": true, "tick": tick, "candidates": candidates,
        "blocked": blocked, "status": "N153_SOURCE_SELECTED_NOT_APPLIED"}
