extends RefCounted
## P2: N92 -> N147 native colony workforce migration on ONE N39 World.
## READ-ONLY. It never spawns a population, mints credits, posts N104
## passenger contracts or teleports across missing N4 directed links.
const Colony = preload("res://scripts/ported/n92_colony_development.gd")
const Planner = preload("res://scripts/sim/phase1/n147_native_colony_migration_planner.gd")
const Commission = preload("res://scripts/sim/phase1/n147_native_colony_migration_commission.gd")
const Catalog = preload("res://scripts/sim/ship_catalog.gd")
const Transit = preload("res://scripts/sim/ship_transit.gd")

static func _route_cost(graph: RefCounted, positions: Dictionary,
        origin: String, destination: String, speed: float, rate: float,
        scale: float) -> Dictionary:
    if graph == null or origin.is_empty() or destination.is_empty():
        return {"ok": false, "reason": "n142_missing_physical_endpoint"}
    var path: Dictionary = graph.shortest_path(origin, destination)
    if not bool(path.get("reachable", false)):
        return {"ok": false, "reason": "n142_no_directed_passenger_route"}
    var locations: Array = path.get("locations", [])
    if locations.is_empty() or str(locations[0]) != origin or str(locations[-1]) != destination:
        return {"ok": false, "reason": "n142_invalid_directed_path"}
    var distance: float = float(path.get("distance", -1.0))
    if not is_finite(distance) or distance < 0.0 or distance > float(Planner.MAX_U32) or distance != floor(distance):
        return {"ok": false, "reason": "n142_invalid_native_distance"}
    if speed <= 0.0 or rate <= 0.0 or scale <= 0.0 or not is_finite(scale):
        return {"ok": false, "reason": "n14_missing_real_flight_specs"}
    var fuel: float = 0.0
    for i in range(1, locations.size()):
        var a: String = str(locations[i - 1])
        var b: String = str(locations[i])
        var directed: bool = false
        for edge in graph.outgoing(a):
            if str(edge.get("to", "")) == b:
                directed = true
                break
        if not directed or not (positions.get(a) is Vector2) or not (positions.get(b) is Vector2):
            return {"ok": false, "reason": "n14_unmapped_real_leg"}
        var length: float = (positions[a] as Vector2).distance_to(positions[b])
        if not is_finite(length) or length <= 0.0:
            return {"ok": false, "reason": "n14_invalid_real_leg_geometry"}
        fuel += float(maxi(1, ceili(length / (Transit.BASE_VELOCITY * speed * scale)))) * rate * scale
    return {"ok": is_finite(fuel), "fuel": fuel,
        "distance": int(distance), "route": locations}

static func _full_fuel(world: Dictionary, graph: RefCounted,
        positions: Dictionary, ship: Dictionary, source: String,
        destination: String, scale: float) -> bool:
    var spec: Dictionary = Catalog.spec(str(ship.get("class", "")))
    if spec.is_empty() or not (ship.get("cargo") is Dictionary) or not ship["cargo"].is_empty():
        return false
    var speed: float = Catalog.effective_speed(str(ship.get("class", "")), str(ship.get("size", "")))
    var rate: float = float(spec.get("fuel_consumption_base", 0.0))
    var here: String = str(ship.get("location", ""))
    var first: Dictionary = _route_cost(graph, positions, here, source, speed, rate, scale)
    var second: Dictionary = _route_cost(graph, positions, source, destination, speed, rate, scale)
    return first.get("ok", false) and second.get("ok", false) and (
        float(ship.get("fuel", 0.0)) + 0.0001 >= float(first.get("fuel", INF)) + float(second.get("fuel", INF)))

static func observe(world: Dictionary, graph: RefCounted,
        resolver: RefCounted, positions: Dictionary,
        tick: int, scale: float) -> Dictionary:
    if tick < 1 or graph == null or resolver == null or scale <= 0.0 or not is_finite(scale):
        return {"ok": false, "reason": "n147_missing_native_tick_or_routes"}
    for field in ["facilities", "markets", "populations", "ships",
            "faction_treasuries", "contract_board"]:
        if not (world.get(field) is Dictionary):
            return {"ok": false, "reason": "n147_missing_canonical_" + field}
    var board_value: Variant = world["contract_board"].get("contracts", null)
    if not (board_value is Dictionary):
        return {"ok": false, "reason": "n147_missing_one_contract_board"}
    var board: Dictionary = board_value
    var contracts: Array = []
    var ids: Array = board.keys()
    ids.sort()
    for id in ids:
        var c: Dictionary = board[id]
        var payer: String = str(c.get("requestor_id", ""))
        if payer.begins_with("faction/"):
            payer = payer.substr(8)
        contracts.append({
            "id": str(id), "type": str(c.get("contract_type", "")),
            "requestor_id": payer,
            "destination_location": str(c.get("destination_location", "")),
            "status": str(c.get("status", "")),
            "reserved_credits": int(c.get("reserved", 0)),
            "fulfiller_id": c.get("fulfiller_id", null)})
    var colonies: Array = []
    var stations: Array = []
    var fac_ids: Array = world["facilities"].keys()
    fac_ids.sort()
    for fid in fac_ids:
        var f: Dictionary = world["facilities"][fid]
        var location: String = str(f.get("location", ""))
        if str(f.get("type", "")) == "station":
            stations.append({"facility_type": "station",
                "faction_id": str(f.get("faction", "")), "location": location})
        if str(f.get("type", "")) != "station" or not location.ends_with("-colony"):
            continue
        var owner: String = str(f.get("faction", ""))
        var local_facilities: Array = []
        for other_id in fac_ids:
            var other: Dictionary = world["facilities"][other_id]
            if str(other.get("location", "")) == location and str(other.get("faction", "")) == owner:
                local_facilities.append({"type": str(other.get("type", "")),
                    "crew_count": int(other.get("crew_count", 0))})
        var people_count: int = 0
        var food_per: float = 0.0
        var water_per: float = 0.0
        var pop_ids: Array = world["populations"].keys()
        pop_ids.sort()
        for pid in pop_ids:
            var p: Dictionary = world["populations"][pid]
            if str(p.get("location", "")) != location or str(p.get("faction", "")) != owner:
                continue
            people_count += int(p.get("count", 0))
            food_per += float(p.get("consumption", {}).get("food", 0.0))
            water_per += float(p.get("consumption", {}).get("water", 0.0))
        var market: Dictionary = world["markets"].get(location, {})
        var unique: bool = not market.is_empty() and str(market.get("owner", "")) == str(fid)
        var pending: String = ""
        for contract in contracts:
            if contract["type"] == "passenger" and contract["requestor_id"] == owner and contract["destination_location"] == location and Planner.outstanding(contract):
                pending = str(contract["id"])
                break
        colonies.append({"faction_id": owner, "location": location,
            "station_type": "station", "population": people_count,
            "facilities": local_facilities,
            "market_count": 1 if unique else 0,
            "market_owned_by_station": unique,
            "stock": market.get("supply", {}).duplicate(true),
            "demand": market.get("demand", {}).duplicate(true),
            "food_per_purchase": food_per,
            "water_per_purchase": water_per,
            "pending_passenger_contract": pending})
    var views: Array = Colony.observe(colonies)
    var people: Array = []
    var pop_ids: Array = world["populations"].keys()
    pop_ids.sort()
    for pid in pop_ids:
        var p: Dictionary = world["populations"][pid]
        people.append({"faction_id": str(p.get("faction", "")),
            "location": str(p.get("location", "")),
            "population_count": int(p.get("count", 0))})
    var distances: Dictionary = {}
    var origins: Dictionary = {}
    for station in stations:
        origins[str(station["location"])] = true
    var ships: Array = []
    var ship_ids: Array = world["ships"].keys()
    ship_ids.sort()
    for id in ship_ids:
        var ship: Dictionary = world["ships"][id]
        var here: String = str(ship.get("location", ""))
        if not here.is_empty():
            origins[here] = true
        ships.append({
            "id": str(id), "faction_id": str(ship.get("faction_id", "")),
            "class": str(ship.get("class", "")),
            "location": here, "has_native_cargo": ship.get("cargo") is Dictionary,
            "active_contract_id": ship.get("active_contract_id", null),
            "in_transit": not (ship.get("transit", {}) as Dictionary).is_empty(),
            "fuel": float(ship.get("fuel", 0.0))})
    var targets: Dictionary = {}
    for view in views:
        targets[str(view.get("location", ""))] = true
    for station in stations:
        targets[str(station["location"])] = true
    for from in origins:
        var row: Dictionary = {}
        for to in targets:
            var source_path: Dictionary = graph.shortest_path(str(from), str(to))
            var distance: float = float(source_path.get("distance", -1.0))
            if source_path.get("reachable", false) and is_finite(distance) and distance >= 0.0 and distance <= float(Planner.MAX_U32) and distance == floor(distance):
                row[to] = int(distance)
        distances[from] = row
    var native: Dictionary = {
        "treasuries": world["faction_treasuries"].duplicate(true),
        "stations": stations, "households": people,
        "ships": ships, "ship_classes": Catalog.CLASSES,
        "contracts": contracts, "physical_distances": distances}
    var result: Dictionary = Planner.plan(views, native)
    if not result.get("ok", false):
        return result
    var ready: Array = []
    var blocked: Array = []
    var factions: Array = result.get("plans", {}).keys()
    factions.sort()
    for faction in factions:
        var p: Dictionary = result["plans"][faction]
        var can_fly: bool = false
        for id in ship_ids:
            var ship: Dictionary = world["ships"][id]
            if str(ship.get("faction_id", "")) != str(faction) or str(ship.get("current_goal", "")) not in ["", "idle"] or not str(ship.get("active_contract_id", "")).is_empty() or not (ship.get("transit", {}) as Dictionary).is_empty():
                continue
            if int(Catalog.spec(str(ship.get("class", ""))).get("passenger_capacity", 0)) < int(p["quantity"]):
                continue
            if _full_fuel(world, graph, positions, ship,
                    str(p["source"]), str(p["destination"]), scale):
                can_fly = true
                break
        if not can_fly:
            blocked.append({"faction_id": str(faction),
                "reason": "n147_insufficient_full_physical_route_fuel"})
            continue
        var prepared: Dictionary = Commission.prepare_commission(
            native, str(faction), p, tick, 1)
        if not prepared.get("ok", false):
            blocked.append({"faction_id": str(faction),
                "reason": str(prepared.get("reason", "n147_source_commission_rejected"))})
            continue
        ready.append({"faction_id": str(faction),
            "source": str(p["source"]), "destination": str(p["destination"]),
            "quantity": int(p["quantity"]), "payment": int(p["payment"]),
            "status": "N147_PREPARED_NOT_POSTED",
            "reason": "awaiting_real_n104_passenger_embark_disembark_apply"})
    return {"ok": true, "tick": tick, "views": views,
        "ready": ready, "blocked": blocked, "posted": [],
        "status": "N147_NO_ESTABLISHED_COLONIES" if views.is_empty() else "N147_SOURCE_EVALUATED",
        "authority": "read_only_source_n92_n147; one_n39_world_no_money_or_people_changes"}
