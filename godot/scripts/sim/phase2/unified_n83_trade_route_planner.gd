extends RefCounted
## Frozen Rust N83 -> N80 -> N81 -> N84 autonomous trade goal
## on ONE canonical N39 World. Only a real N140-fired, unassigned,
## stationary ship with actual observed market prices may start.
## This module does NOT transfer goods, dock or modify N9 money.
const TradeRoute = preload("res://scripts/sim/ships/ai/native_trade_route_policy.gd")
const Goal = preload("res://scripts/sim/ships/ai/native_ship_goal_policy.gd")
const Personality = preload("res://scripts/sim/ships/ai/native_personality.gd")
const GOAP = preload("res://scripts/sim/ships/ai/native_goap_planner.gd")
const Plans = preload("res://scripts/sim/phase1/n153_native_ship_bt_planning.gd")
const BT = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")
const Paths = preload("res://scripts/sim/phase2/unified_ship_ai_planner.gd")
const Relations = preload("res://scripts/sim/phase1/n150_native_full_faction_relations.gd")

static func stage(world: Dictionary, graph: RefCounted, tick: int,
        fired: Dictionary) -> Dictionary:
    if tick < 1 or graph == null or not (world.get("ships") is Dictionary) or (
            not (world.get("markets") is Dictionary)):
        return {"ok": false, "reason": "n83_no_original_runtime_sources"}
    var pairs: Dictionary = world.get("faction_relations", {})
    if not Relations.validate_pairs(pairs):
        return {"ok": false, "reason": "n83_invalid_original_relations"}
    var ships: Dictionary = world["ships"].duplicate(true)
    var controllers: Dictionary = {}
    var buyer_cash: Dictionary = {}
    for location in world["markets"]:
        var owner_id: String = str(world["markets"][location].get("owner", ""))
        var owner: Dictionary = world.get("facilities", {}).get(owner_id, {})
        if owner.is_empty() or str(owner.get("location", "")) != str(location):
            return {"ok": false, "reason": "n83_market_has_no_real_owner"}
        controllers[str(location)] = str(owner.get("faction", ""))
        buyer_cash[str(location)] = int(owner.get("credits", 0))
    var ids: Array = fired.keys()
    ids.sort()
    var accepted: Array = []
    for ship_id in ids:
        if not ships.has(ship_id) or typeof(fired[ship_id]) != TYPE_INT or (
                int(fired[ship_id]) < 1):
            return {"ok": false, "reason": "n83_wrong_n140_fired_ship"}
        var ship: Dictionary = ships[ship_id]
        if str(ship.get("active_contract_id", "")) != "" or (
                str(ship.get("current_goal", "idle")) not in ["", "idle"] or
                ship.get("current_bt", null) != null or
                not ship.get("transit", {}).is_empty()):
            continue
        var loc: String = str(ship.get("location", ""))
        if loc.is_empty() or not graph.has_location(loc):
            continue
        if not (ship.get("memory") is Dictionary):
            continue
        var known: Variant = ship["memory"].get("price_knowledge", null)
        if not (known is Dictionary) or known.size() < 2:
            continue
        var commerce: Dictionary = {}
        for location in known:
            commerce[str(location)] = Relations.commerce_allowed(
                pairs, str(ship.get("faction_id", "")), str(controllers.get(location, "")))
        var performance: Dictionary = {}
        for raw_key in ship["memory"].get("route_performance", {}):
            var record: Dictionary = ship["memory"]["route_performance"][raw_key]
            var key: String = str(raw_key).replace("\u001f", "|")
            var n: int = int(record.get("attempts", 0))
            performance[key] = {"attempts": n,
                "avg_profit_per_unit": float(record.get("total_profit_per_unit", 0.0)) /
                    float(maxi(1, n))}
        var route: Dictionary = TradeRoute.best_trade_route(
            known, tick, str(ship.get("faction_id", "")),
            controllers, commerce, buyer_cash, performance, true)
        if route.is_empty():
            continue
        var buy: String = str(route.get("buy_location", ""))
        var sell: String = str(route.get("sell_location", ""))
        if buy.is_empty() or sell.is_empty() or buy == sell:
            continue
        var to_buy: Dictionary = Paths._route_legs(graph, loc, buy)
        var to_sell: Dictionary = Paths._route_legs(graph, buy, sell)
        if to_buy.is_empty() or to_sell.is_empty():
            continue
        var tank: float = float(ship.get("fuel_capacity", 0.0))
        if tank <= 0.0 or not is_finite(tank):
            continue
        var fuel_fraction: float = float(ship.get("fuel", 0.0)) / tank
        var cargo_used: int = 0
        for amount in ship.get("cargo", {}).values():
            cargo_used += int(amount)
        # Source N80 must prefer this profitable trade to the idle
        # options. Neither the price memory nor the route makes a
        # physical transaction without N97 and N21.
        var profile: Dictionary = ship.get("personality", {})
        if not Personality.validate(profile):
            profile = Personality.for_class(str(ship.get("class", "")))
        if not Personality.validate(profile):
            continue
        # Native Rust takes contested status from the actual
        # BodyTerritory of each market's host facility, then applies
        # own_market_priority AGAIN during N80 goal scoring. N83's
        # initial margin rank already includes its own source boost.
        var contested: bool = false
        var ownership_weight: float = 0.0
        for endpoint in [buy, sell]:
            var market_owner: String = str(world["markets"][endpoint].get("owner", ""))
            var home: Dictionary = world.get("facilities", {}).get(market_owner, {})
            var body_id: String = str(home.get("body_id", ""))
            var territory: Dictionary = world.get("body_territory", {}).get(body_id, {})
            contested = contested or bool(territory.get("contested", false))
            ownership_weight += 1.25 if str(home.get("faction", "")) == str(ship.get("faction_id", "")) else 1.0
        ownership_weight /= 2.0
        var chosen: Dictionary = Goal.choose_goal({
            "location": loc, "class": str(ship.get("class", "")),
            "fuel_fraction": fuel_fraction,
            "cargo_capacity": int(ship.get("cargo_capacity", 0)),
            "cargo_used": cargo_used,
            # Rust N80 biological morale priority outranks optional
            # trade when a physically occupied N21 rest dock exists.
            "crew_morale": float(ship.get("crew", {}).get("morale", 70.0)),
            "can_rest": not str(ship.get("docked_at", "")).is_empty(),
            "trade": {"profit": int(route.get("estimated_profit", 0)),
                "contested": contested, "ownership_priority": ownership_weight,
                "feasible": true, "combined_retrofit": false},
            "idle_goal": "idle"
        }, profile)
        if not chosen.get("ok", false) or str(chosen.get("name", "")) != "trade_run":
            continue
        var routes: Dictionary = {}
        routes[loc + "|" + buy] = to_buy["legs"].duplicate(true)
        routes[buy + "|" + sell] = to_sell["legs"].duplicate(true)
        var bucket: int = GOAP.fuel_fraction_to_bucket(fuel_fraction)
        var request: Dictionary = Plans.trade_candidate_request(loc, {
            "buy_loc": buy, "sell_loc": sell,
            "commodity": str(route["commodity"])}, bucket, routes)
        if request.is_empty() or not (request.get("loc_map") is Dictionary):
            continue
        var start: Dictionary = GOAP.initial("Origin", bucket)
        start["docked"] = not str(ship.get("docked_at", "")).is_empty()
        var plan: Dictionary = GOAP.plan(start, "trade", request["loc_map"],
            int(request.get("max_depth", 20)), int(request.get(
                "goal", {}).get("fuel_bucket_min", 2)))
        if plan.is_empty() or not (plan.get("actions") is Array):
            continue
        var normalized: Array = []
        var has_unsupported: bool = false
        for raw in plan["actions"]:
            var step: Dictionary = raw.duplicate(true)
            step["kind"] = str(raw.get("type", ""))
            step.erase("type")
            if str(step["kind"]) in ["Refuel", "Refit"]:
                # No ghost gas, module or payment to make GOAP work.
                has_unsupported = true
                break
            normalized.append(step)
        if has_unsupported:
            continue
        var steps: Array = Plans.compile_plan_to_bt_actions(
            normalized, request["loc_map"], routes, true)
        if steps.is_empty():
            continue
        var nodes: Array = []
        for step in steps:
            var node: Dictionary = BT.action(step)
            if node.is_empty():
                has_unsupported = true
                break
            nodes.append(node)
        if has_unsupported:
            continue
        var tree: Dictionary = BT.sequence(nodes)
        if not BT.validate(tree):
            continue
        ship["current_goal"] = "trade_route"
        ship["current_goal_score"] = float(chosen.get("score", 0.0))
        ship["current_bt"] = tree
        ship["planning_source"] = "N83:N80:N81:source_trade_run"
        accepted.append({"ship_id": str(ship_id), "buy": buy, "sell": sell,
            "commodity": str(route["commodity"]), "tick": tick,
            "goap_cost": int(plan.get("cost", 0))})
    return {"ok": true, "changed": not accepted.is_empty(),
        "ships": ships, "ship_next_token": int(world.get("ship_next_token", 0)),
        "next_token": int(world.get("ship_next_token", 0)),
        "accepted": accepted, "tick": tick}
