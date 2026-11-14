extends RefCounted
## SOURCE ONLY: frozen Rust agents/ship/behavior.rs choose_ice_mining_trip
## and N80 scoring. The original N103 ice deposit, N15 hold and source
## market buyer belong to ONE current N39 World. No invented ice or cash.
## This proposal is intentionally NOT scheduled by N158 while the shared
## V2 crisis lease owns N39/N158. N84/N90/N97 settlement must be wired
## before activating this source-only adapter.
const Ice = preload("res://scripts/sim/ships/ai/native_ice_mining_policy.gd")
const Goal = preload("res://scripts/sim/ships/ai/native_ship_goal_policy.gd")
const Personality = preload("res://scripts/sim/ships/ai/native_personality.gd")
const Catalog = preload("res://scripts/sim/ship_catalog.gd")
const BT = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")
const MAX_U32: int = 4294967295

static func _locations(world: Dictionary, graph: RefCounted,
        ship_location: String) -> Array:
    var names: Dictionary = {}
    names[ship_location] = true
    for location in world.get("markets", {}):
        names[str(location)] = true
    var snapshot: Dictionary = graph.snapshot()
    for edge in snapshot.get("edges", []):
        names[str(edge.get("from", ""))] = true
        names[str(edge.get("to", ""))] = true
    var result: Array = names.keys()
    result.sort()
    return result

static func _route(graph: RefCounted, start: String, finish: String) -> Array:
    if start == finish:
        return []
    if not graph.has_location(start) or not graph.has_location(finish):
        return []
    var path: Dictionary = graph.shortest_path(start, finish)
    if not bool(path.get("reachable", false)):
        return []
    var legs: Array = path.get("locations", [])
    if legs.size() < 2 or str(legs[0]) != start or str(legs[-1]) != finish:
        return []
    var actions: Array = []
    for i in range(1, legs.size()):
        var a: String = str(legs[i - 1])
        var dest: String = str(legs[i])
        var valid: bool = false
        for edge in graph.outgoing(a):
            if str(edge.get("to", "")) == dest and (
                    float(edge.get("distance", -1.0)) > 0.0 and
                    is_finite(float(edge.get("distance", -1.0)))):
                valid = true
                break
        if not valid:
            return []
        actions.append(BT.action({"kind": "Travel", "destination": dest}))
    return actions

static func _physical_sources(world: Dictionary, graph: RefCounted,
        resolver: RefCounted, ship: Dictionary) -> Dictionary:
    var location: String = str(ship.get("location", ""))
    var system_id: String = str(ship.get("system_id", ""))
    var faction: String = str(ship.get("faction_id", ""))
    var names: Array = _locations(world, graph, location)
    var sites: Array = []
    for loc in names:
        if not graph.has_location(str(loc)) or (
                resolver.system_for_location(str(loc)) != system_id):
            continue
        var body_id: String = resolver.body_for_location(str(loc))
        var richness: Variant = world.get("bodies", {}).get(
            body_id, {}).get("resources", {}).get("ice", null)
        if not (richness is int or richness is float) or (
                not is_finite(float(richness)) or float(richness) <= 0.0):
            continue
        sites.append({"location": str(loc), "body_id": body_id,
            "richness": float(richness)})
    var depots: Array = []
    var observed: Dictionary = ship.get("memory", {}).get(
        "price_knowledge", {})
    var markets: Dictionary = world.get("markets", {})
    var depot_locations: Array = markets.keys()
    depot_locations.sort()
    for depot_location in depot_locations:
        var depot_loc: String = str(depot_location)
        if not graph.has_location(depot_loc) or (
                resolver.system_for_location(depot_loc) != system_id):
            continue
        var market: Dictionary = markets[depot_location]
        var facility: Dictionary = world.get("facilities", {}).get(
            str(market.get("owner", "")), {})
        if str(facility.get("type", "")) != "station" or (
                bool(facility.get("abandoned", false)) or
                str(facility.get("faction", "")) != faction or
                str(facility.get("location", "")) != depot_loc or
                int(facility.get("docking_capacity", 0)) < 1):
            continue
        # Source knowledge is a real ship observation, not a copy of
        # omniscient prices from unrelated live markets. The station
        # wallet and deposit are canonical N9/N39 data.
        var quotes: Dictionary = observed.get(depot_loc, {})
        if not (quotes.get("ice") is Dictionary) or (
                not (quotes.get("fuel") is Dictionary)):
            continue
        var ice_price: Variant = quotes["ice"].get("price", null)
        var fuel_price: Variant = quotes["fuel"].get("price", null)
        if not (ice_price is int or ice_price is float) or (
                not (fuel_price is int or fuel_price is float)) or (
                not is_finite(float(ice_price)) or
                not is_finite(float(fuel_price)) or
                float(ice_price) <= 0.0 or float(fuel_price) < 0.0):
            continue
        depots.append({"location": depot_loc, "faction_id": faction,
            "buyer_credits": int(facility.get("credits", -1)),
            "ice_unit_price": float(ice_price),
            "fuel_unit_price": float(fuel_price)})
    var distances: Dictionary = {}
    for depot in depots:
        for site in sites:
            var base: String = str(depot["location"])
            var target: String = str(site["location"])
            var outward: Dictionary = graph.shortest_path(base, target)
            var back: Dictionary = graph.shortest_path(target, base)
            if not bool(outward.get("reachable", false)) or not (
                    bool(back.get("reachable", false))):
                continue
            var out_distance: float = float(outward.get("distance", -1.0))
            var back_distance: float = float(back.get("distance", -1.0))
            if not is_finite(out_distance) or not is_finite(back_distance) or (
                    out_distance < 0.0 or back_distance < 0.0 or
                    out_distance > float(MAX_U32) or
                    back_distance > float(MAX_U32) or
                    out_distance != floor(out_distance)):
                continue
            # Frozen Registry::travel_distance is an unsigned integer
            # for this selector. N14 still checks each actual leg.
            distances[base + "\u001f" + target] = int(out_distance)
    return {"sites": sites, "depots": depots, "distances": distances}

static func stage(world: Dictionary, graph: RefCounted,
        resolver: RefCounted, tick: int, fired: Dictionary) -> Dictionary:
    if tick < 1 or graph == null or resolver == null or (
            not resolver.has_method("body_for_location") or
            not resolver.has_method("system_for_location") or
            not graph.has_method("snapshot") or
            not (world.get("ships") is Dictionary) or
            not (world.get("bodies") is Dictionary) or
            not (world.get("markets") is Dictionary) or
            not (world.get("facilities") is Dictionary)):
        return {"ok": false, "reason": "n103_missing_actual_source_authorities"}
    var ships: Dictionary = world["ships"].duplicate(true)
    var accepted: Array = []
    var blocked: Array = []
    var ids: Array = fired.keys()
    ids.sort()
    for ship_id in ids:
        if not ships.has(ship_id) or typeof(fired[ship_id]) != TYPE_INT or int(fired[ship_id]) < 1:
            return {"ok": false, "reason": "n103_foreign_n140_fired_ship"}
        var ship: Dictionary = ships[ship_id]
        if str(ship.get("class", "")) != "miner" or (
                str(ship.get("current_goal", "idle")) not in ["", "idle"] or
                not str(ship.get("active_contract_id", "")).is_empty() or
                ship.get("current_bt", null) != null or
                not (ship.get("transit", {}) is Dictionary) or
                not ship["transit"].is_empty()):
            continue
        var loc: String = str(ship.get("location", ""))
        if not graph.has_location(loc) or (
                resolver.system_for_location(loc) != str(ship.get("system_id", ""))):
            blocked.append({"ship_id": str(ship_id), "reason": "n103_unmapped_real_miner"})
            continue
        var profile: Dictionary = ship.get("personality", {})
        if not Personality.validate(profile):
            profile = Personality.for_class("miner")
        if not Personality.validate(profile):
            return {"ok": false, "reason": "n103_missing_native_miner_personality"}
        var catalog: Dictionary = Catalog.spec("miner")
        var fuel_rate: float = float(catalog.get("fuel_consumption_base", -1.0))
        var speed: float = float(ship.get("speed_modifier", Catalog.effective_speed(
            str(ship.get("class", "")), str(ship.get("size", "")))))
        if not is_finite(fuel_rate) or fuel_rate < 0.0 or (
                not is_finite(speed) or speed <= 0.0):
            blocked.append({"ship_id": str(ship_id), "reason": "n103_native_fuel_geometry_invalid"})
            continue
        var carried: int = int(ship.get("cargo", {}).get("ice", 0))
        var used: int = 0
        for qty in ship.get("cargo", {}).values():
            if typeof(qty) != TYPE_INT or int(qty) < 0:
                return {"ok": false, "reason": "n103_corrupt_real_hold"}
            used += int(qty)
        var capacity: int = int(ship.get("cargo_capacity", 0))
        if used > capacity:
            return {"ok": false, "reason": "n103_overloaded_original_ship"}
        var physical: Dictionary = _physical_sources(
            world, graph, resolver, ship)
        var candidate: Dictionary = Ice.choose_ice_mining_trip(
            loc, str(ship.get("faction_id", "")), carried,
            capacity - used, fuel_rate, speed, profile,
            physical["sites"], physical["depots"], physical["distances"])
        if not candidate.get("ok", false):
            blocked.append({"ship_id": str(ship_id),
                "reason": str(candidate.get("reason", "source_no_profitable_trip"))})
            continue
        var chosen: Dictionary = candidate["proposal"]
        var tank: float = float(ship.get("fuel_capacity", -1.0))
        var remain: float = float(ship.get("fuel", -1.0))
        if tank <= 0.0 or not is_finite(tank) or not is_finite(remain) or remain < 0.0:
            continue
        var preference: Dictionary = Goal.choose_goal({
            "location": loc, "class": "miner",
            "fuel_fraction": remain / tank,
            "cargo_capacity": capacity, "cargo_used": used,
            "mining_candidate": chosen, "idle_goal": "idle",
            "crew_morale": float(ship.get("crew", {}).get("morale", 70.0)),
            "can_rest": not str(ship.get("docked_at", "")).is_empty()
        }, profile)
        if not preference.get("ok", false) or not (
                str(preference.get("name", "")) in ["mine_ice", "deliver_mined_ice"]):
            continue
        var nodes: Array = []
        var cursor: String = loc
        var valid: bool = true
        for action in chosen["actions"]:
            var kind: String = str(action.get("action", ""))
            if kind == "Travel":
                var target: String = str(action.get("destination", ""))
                var route: Array = _route(graph, cursor, target)
                if cursor != target and route.is_empty():
                    valid = false
                    break
                nodes.append_array(route)
                cursor = target
            else:
                var leaf: Dictionary = action.duplicate(true)
                leaf.erase("action")
                leaf["kind"] = kind
                if kind == "Mine" and (
                        resolver.body_for_location(cursor) != str(
                        leaf.get("body_id", "")) or
                        cursor != str(leaf.get("location", ""))):
                    valid = false
                    break
                nodes.append(BT.action(leaf))
        if not valid:
            blocked.append({"ship_id": str(ship_id), "reason": "n103_unreachable_original_mining_bt"})
            continue
        var tree: Dictionary = BT.sequence(nodes)
        if not BT.validate(tree):
            return {"ok": false, "reason": "n103_invalid_source_mining_bt"}
        ship["current_goal"] = "mine"
        ship["current_goal_score"] = float(preference["score"])
        ship["current_bt"] = tree
        ship["last_plan_tick"] = tick
        ship["planning_source"] = "N103:N80:rust_ice_mining_goal"
        accepted.append({"ship_id": str(ship_id),
            "kind": str(chosen["name"]),
            "site": str(chosen["site_location"]),
            "depot": str(chosen["depot_location"]),
            "quantity": int(chosen["quantity"]),
            "tick": tick})
    return {"ok": true, "changed": not accepted.is_empty(),
        "ships": ships, "next_token": int(world.get("ship_next_token", 0)),
        "accepted": accepted, "blocked": blocked, "tick": tick,
        "status": "SOURCE_PREPARED_NOT_EXECUTED"}
