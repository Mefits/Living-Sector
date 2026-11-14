extends RefCounted
## P2 N80 SOURCE ONLY. Frozen Rust agents/ship/behavior.rs:
## smart_idle_fallback -> try_build_explore_bt -> N84 source actions.
## Called by the future one-N158 integration point, not by an extra tick.
## Does NOT build gates, assign contracts, transfer money or move ships.
const Idle = preload("res://scripts/sim/ships/ai/native_ship_idle_policy.gd")
const Goals = preload("res://scripts/sim/ships/ai/native_ship_goal_policy.gd")
const Personality = preload("res://scripts/sim/ships/ai/native_personality.gd")
const BT = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")
const BOARD_DWELL_SECONDS: int = 5 # frozen ShipComponents EXPLORE_CHECK_BOARD_SECONDS

static func _route(graph: RefCounted, origin: String, destination: String) -> Array:
    if not graph.has_location(origin) or not graph.has_location(destination):
        return []
    if origin == destination:
        return []
    var result: Dictionary = graph.shortest_path(origin, destination)
    if not bool(result.get("reachable", false)):
        return []
    var points: Array = result.get("locations", [])
    if points.size() < 2 or str(points[0]) != origin or str(points[-1]) != destination:
        return []
    var steps: Array = []
    for index in range(1, points.size()):
        var start: String = str(points[index - 1])
        var dest: String = str(points[index])
        var legal: bool = false
        for edge in graph.outgoing(start):
            if str(edge.get("to", "")) == dest and (
                    float(edge.get("distance", -1.0)) > 0.0 and
                    is_finite(float(edge.get("distance", -1.0)))):
                legal = true
                break
        if not legal:
            return []
        steps.append(BT.action({"kind": "Travel", "destination": dest}))
    return steps

static func _stations(world: Dictionary, resolver: RefCounted,
        system_id: String, excluded: String, graph: RefCounted) -> Array:
    var matches: Array = []
    var markets: Dictionary = world.get("markets", {})
    for location in markets:
        var loc: String = str(location)
        if resolver.system_for_location(loc) != system_id:
            continue
        var owner_id: String = str(markets[location].get("owner", ""))
        var station: Dictionary = world.get("facilities", {}).get(owner_id, {})
        if str(station.get("location", "")) != loc or (
                str(station.get("type", "")) != "station" or
                bool(station.get("abandoned", false)) or
                int(station.get("docking_capacity", 0)) < 1 or
                not graph.has_location(loc)):
            continue
        matches.append(loc)
    matches.sort()
    return matches

## Only mutually paired ACTUAL gate facilities qualify. Frozen Rust
## discovers gate_pairs via the registry; never add a synthetic N4 edge.
static func _neighbor_gates(world: Dictionary, graph: RefCounted,
        resolver: RefCounted, ship: Dictionary) -> Array:
    var found: Array = []
    var facilities: Dictionary = world.get("facilities", {})
    var at: String = str(ship.get("location", ""))
    var here: String = str(ship.get("system_id", ""))
    var recent: Array = ship.get("memory", {}).get("recent_systems", [])
    var keys: Array = facilities.keys()
    keys.sort()
    for gate_id in keys:
        var gate: Dictionary = facilities[gate_id]
        if str(gate.get("type", "")) != "gate" or (
                bool(gate.get("abandoned", false)) or
                not (gate.get("gate_link") is Dictionary)):
            continue
        var mate_id: String = str(gate["gate_link"].get("paired_gate_id", ""))
        var mate: Dictionary = facilities.get(mate_id, {})
        if str(mate.get("type", "")) != "gate" or (
                bool(mate.get("abandoned", false)) or
                not (mate.get("gate_link") is Dictionary) or
                str(mate["gate_link"].get("paired_gate_id", "")) != str(gate_id)):
            continue
        var source: String = str(gate.get("location", ""))
        var destination: String = str(mate.get("location", ""))
        var source_system: String = resolver.system_for_body(
            str(gate.get("body_id", "")))
        var target_system: String = resolver.system_for_body(
            str(mate.get("body_id", "")))
        if source.is_empty() or destination.is_empty() or (
                source == destination or source_system.is_empty() or
                target_system.is_empty() or source_system == target_system or
                source_system != here or not graph.has_location(source) or
                not graph.has_location(destination)):
            continue
        var to_gate: Array = _route(graph, at, source)
        if at != source and to_gate.is_empty():
            continue
        # The N108 physical and financial Apply remains the final authority.
        var cargo_used: int = 0
        for qty in ship.get("cargo", {}).values():
            if typeof(qty) != TYPE_INT or int(qty) < 0:
                cargo_used = -1
                break
            cargo_used += int(qty)
        var flat: int = int(gate["gate_link"].get("fee_flat", -1))
        var unit: int = int(gate["gate_link"].get("fee_per_cargo_unit", -1))
        if cargo_used < 0 or flat < 0 or unit < 0 or (
                cargo_used > 0 and unit > (9223372036854775807 - flat) / cargo_used):
            continue
        if int(ship.get("credits", -1)) < flat + unit * cargo_used:
            continue
        var landing_options: Array = _stations(world, resolver,
            target_system, destination, graph)
        var landing: String = ""
        var to_landing: Array = []
        for loc in landing_options:
            var leg: Array = _route(graph, destination, str(loc))
            if str(loc) == destination or not leg.is_empty():
                landing = str(loc)
                to_landing = leg
                break
        # Rust's no-station fallback attempts Dock at a gate, but a
        # real N21 dock may not exist. Fail closed until a port exists.
        if landing.is_empty():
            continue
        found.append({"source": source, "destination": destination,
            "target_system": target_system, "station": landing,
            "to_gate": to_gate, "to_station": to_landing,
            "unvisited": not recent.has(target_system)})
    found.sort_custom(func(a, b):
        if bool(a["unvisited"]) != bool(b["unvisited"]):
            return bool(a["unvisited"])
        if str(a["source"]) != str(b["source"]):
            return str(a["source"]) < str(b["source"])
        return str(a["destination"]) < str(b["destination"])
    )
    return found

static func stage(world: Dictionary, graph: RefCounted,
        resolver: RefCounted, tick: int, fired: Dictionary) -> Dictionary:
    if tick < 1 or graph == null or resolver == null or (
            not resolver.has_method("system_for_location") or
            not resolver.has_method("system_for_body") or
            not (world.get("ships") is Dictionary) or
            not (world.get("facilities") is Dictionary) or
            not (world.get("markets") is Dictionary)):
        return {"ok": false, "reason": "n80_missing_original_explore_authorities"}
    var ships: Dictionary = world["ships"].duplicate(true)
    var ids: Array = fired.keys()
    ids.sort()
    var accepted: Array = []
    var blocked: Array = []
    for ship_id in ids:
        if not ships.has(ship_id) or typeof(fired[ship_id]) != TYPE_INT or int(fired[ship_id]) < 1:
            return {"ok": false, "reason": "n80_foreign_n140_fired_ship"}
        var ship: Dictionary = ships[ship_id]
        if str(ship.get("active_contract_id", "")) != "" or (
                str(ship.get("current_goal", "idle")) not in ["", "idle"] or
                ship.get("current_bt", null) != null or
                not (ship.get("transit", {}) is Dictionary) or
                not ship["transit"].is_empty()):
            continue
        var at: String = str(ship.get("location", ""))
        if at.is_empty() or not graph.has_location(at) or (
                resolver.system_for_location(at) != str(ship.get("system_id", ""))):
            blocked.append({"ship_id": str(ship_id), "reason": "not_at_mapped_source_system"})
            continue
        var tank: float = float(ship.get("fuel_capacity", 0.0))
        var fuel: float = float(ship.get("fuel", 0.0))
        if not is_finite(tank) or tank <= 0.0 or not is_finite(fuel) or fuel < 0.0:
            blocked.append({"ship_id": str(ship_id), "reason": "invalid_actual_fuel"})
            continue
        var profile: Dictionary = ship.get("personality", {})
        if not Personality.validate(profile):
            profile = Personality.for_class(str(ship.get("class", "")))
        if not Personality.validate(profile):
            blocked.append({"ship_id": str(ship_id), "reason": "missing_original_personality"})
            continue
        var neighbors: Array = _neighbor_gates(world, graph, resolver, ship)
        var destinations: Array = []
        for item in neighbors:
            destinations.append(str(item["destination"]))
        var idle: Dictionary = Idle.choose({
            "idle_ticks": int(ship.get("lifecycle", {}).get("idle_ticks", 0)),
            "credits": int(ship.get("credits", 0)),
            "fuel_fraction": fuel / tank,
            "reachable_unvisited_neighbors": destinations,
            "docked": not str(ship.get("docked_at", "")).is_empty(),
            "dockable_here": world.get("markets", {}).has(at),
            "reachable_same_system_station": ""
        }, profile)
        if not idle.get("ok", false) or str(idle.get("name", "")) != "explore":
            continue
        var chosen_gate: Dictionary = {}
        for pair in neighbors:
            if str(pair["destination"]) == str(idle["destination"]):
                chosen_gate = pair
                break
        if chosen_gate.is_empty():
            continue
        var used: int = 0
        for amount in ship.get("cargo", {}).values():
            used += int(amount)
        var chosen: Dictionary = Goals.choose_goal({
            "location": at, "class": str(ship.get("class", "")),
            "fuel_fraction": fuel / tank,
            "cargo_capacity": int(ship.get("cargo_capacity", 0)),
            "cargo_used": used, "idle_goal": "explore",
            "crew_morale": float(ship.get("crew", {}).get("morale", 70.0)),
            "can_rest": not str(ship.get("docked_at", "")).is_empty()
        }, profile)
        if not chosen.get("ok", false) or str(chosen.get("name", "")) != "explore":
            continue
        var nodes: Array = []
        if not str(ship.get("docked_at", "")).is_empty():
            nodes.append(BT.action({"kind": "Undock"}))
        nodes.append_array(chosen_gate["to_gate"])
        nodes.append(BT.action({"kind": "GateJump",
            "src_gate": str(chosen_gate["source"]),
            "dest_gate": str(chosen_gate["destination"])}))
        nodes.append_array(chosen_gate["to_station"])
        nodes.append(BT.action({"kind": "Dock"}))
        nodes.append(BT.action({"kind": "DockDwell",
            "seconds": BOARD_DWELL_SECONDS}))
        nodes.append(BT.action({"kind": "Undock"}))
        var tree: Dictionary = BT.sequence(nodes)
        if not BT.validate(tree):
            return {"ok": false, "reason": "n80_source_exploration_bt_invalid"}
        ship["current_goal"] = "explore"
        ship["current_goal_score"] = float(chosen["score"])
        ship["current_bt"] = tree
        ship["last_plan_tick"] = tick
        ship["planning_source"] = "N80:rust_smart_idle_gate_explore"
        accepted.append({"ship_id": str(ship_id),
            "source_gate": str(chosen_gate["source"]),
            "destination_gate": str(chosen_gate["destination"]),
            "landing_market": str(chosen_gate["station"]),
            "target_system": str(chosen_gate["target_system"]),
            "tick": tick})
    return {"ok": true, "changed": not accepted.is_empty(),
        "ships": ships, "next_token": int(world.get("ship_next_token", 0)),
        "accepted": accepted, "blocked": blocked, "tick": tick,
        "status": "SOURCE_PREPARED_NOT_EXECUTED"}
