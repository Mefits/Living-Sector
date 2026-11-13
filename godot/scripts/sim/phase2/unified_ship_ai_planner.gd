extends RefCounted
## P2 N80 -> N81 -> N84 acceptance plan, from ORIGINAL Rust ported code.
## No alternate scoring / Dijkstra / behavior tree. Plan does not move cargo.
const GoalPolicy = preload("res://scripts/sim/ships/ai/native_ship_goal_policy.gd")
const Personality = preload("res://scripts/sim/ships/ai/native_personality.gd")
const Goap = preload("res://scripts/sim/ships/ai/native_goap_planner.gd")
const Plans = preload("res://scripts/sim/phase1/n153_native_ship_bt_planning.gd")
const Bt = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")

static func _route_legs(graph: RefCounted, from: String, to: String) -> Dictionary:
    var shortest: Dictionary = graph.shortest_path(from, to)
    if not bool(shortest.get("reachable", false)):
        return {}
    var raw: Array = shortest.get("locations", [])
    var legs: Array = []
    for i in range(1, raw.size()):
        var a: String = str(raw[i - 1])
        var b: String = str(raw[i])
        var actual: Dictionary = {}
        for edge in graph.outgoing(a):
            if str(edge.get("to", "")) == b:
                actual = edge
                break
        if actual.is_empty():
            return {}
        var distance: float = float(actual.get("distance", -1.0))
        if not is_finite(distance) or distance <= 0.0:
            return {}
        legs.append({"from": a, "to": b, "kind": "travel",
            "distance": distance})
    return {"legs": legs, "distance": float(shortest["distance"])}

static func propose(ship: Dictionary, selected: Dictionary,
        graph: RefCounted) -> Dictionary:
    var from: String = str(ship.get("location", ""))
    var source: String = str(selected.get("source", ""))
    var dest: String = str(selected.get("destination", ""))
    var cid: String = str(selected.get("contract_id", ""))
    var good: String = str(selected.get("commodity", ""))
    var quantity: int = int(selected.get("quantity", 0))
    if graph == null or from.is_empty() or source.is_empty() or dest.is_empty() or cid.is_empty() or quantity < 1:
        return {"ok": false, "reason": "incomplete_real_delivery_goal"}
    var profile: Dictionary = ship.get("personality", {})
    var provenance: String = "persisted_native_personality"
    if not Personality.validate(profile):
        # Source Rust Personality::for_class is a deterministic native
        # FALLBACK, not a claim that frozen seeder random draws are known.
        profile = Personality.for_class(str(ship.get("class", "")))
        provenance = "native_class_fallback_pending_seed_rng"
    if not Personality.validate(profile):
        return {"ok": false, "reason": "missing_source_personality"}
    var tank: float = float(ship.get("fuel_capacity", 0.0))
    var remaining: float = float(ship.get("fuel", 0.0))
    if not is_finite(tank) or tank <= 0.0 or not is_finite(remaining):
        return {"ok": false, "reason": "invalid_native_fuel"}
    var used: int = 0
    for amount in ship.get("cargo", {}).values():
        used += int(amount)
    var candidate: Dictionary = {
        "name": "fulfill_delivery", "profit": int(selected.get("profit", 0)),
        "ownership_priority": float(selected.get("ownership_priority", 1.0)),
        "contested": false, "feasible": true, "own_strategy": false,
        "combined_retrofit": false}
    var scored: Dictionary = GoalPolicy.choose_goal({
        "location": from, "class": str(ship.get("class", "")),
        "fuel_fraction": remaining / tank,
        "cargo_capacity": int(ship.get("cargo_capacity", 0)),
        "cargo_used": used, "contract": candidate,
        "idle_goal": "idle"
    }, profile)
    if not scored.get("ok", false):
        return {"ok": false, "reason": "n80_" + str(scored.get("reason", "rejected"))}
    if str(scored.get("name", "")) != "fulfill_delivery":
        return {"ok": false, "reason": "n80_prefers_" + str(scored.get("name", ""))}
    var to_source: Dictionary = _route_legs(graph, from, source)
    var to_dest: Dictionary = _route_legs(graph, source, dest)
    if to_source.is_empty() or to_dest.is_empty():
        return {"ok": false, "reason": "native_n4_route_unavailable"}
    var route_legs: Dictionary = {}
    route_legs[from + "|" + source] = to_source["legs"]
    route_legs[source + "|" + dest] = to_dest["legs"]
    var fuel_bucket: int = Goap.fuel_fraction_to_bucket(remaining / tank)
    var request: Dictionary = Plans.contract_candidate_request(from, {
        "kind": "Delivery", "source": source, "destination": dest,
        "id": cid, "commodity": good, "quantity": quantity
    }, fuel_bucket, route_legs)
    if request.is_empty() or not (request.get("loc_map") is Dictionary):
        return {"ok": false, "reason": "n153_native_plan_request_rejected"}
    var start_state: Dictionary = Goap.initial("Origin", fuel_bucket)
    start_state["docked"] = not str(ship.get("docked_at", "")).is_empty()
    var goap: Dictionary = Goap.plan(start_state,
        "delivery", request["loc_map"], int(request.get("max_depth", 20)),
        int(request.get("goal", {}).get("fuel_bucket_min", 0)))
    if goap.is_empty() or not (goap.get("actions") is Array) or goap["actions"].is_empty():
        return {"ok": false, "reason": "n81_no_valid_delivery_plan"}
    var normalized: Array = []
    for raw in goap["actions"]:
        if not (raw is Dictionary):
            return {"ok": false, "reason": "n81_invalid_action"}
        var spec: Dictionary = raw.duplicate(true)
        spec["kind"] = str(raw.get("type", ""))
        spec.erase("type")
        # No free refuelling/retrofitting in P2. Those N88/N97 leaves
        # must have a real physical paid Apply before acceptance.
        if str(spec["kind"]) in ["Refuel", "Refit"] or str(spec["kind"]).is_empty():
            return {"ok": false, "reason": "n81_requires_unwired_paid_action"}
        normalized.append(spec)
    var expanded: Array = Plans.compile_plan_to_bt_actions(
        normalized, request["loc_map"], route_legs, true)
    if expanded.is_empty():
        return {"ok": false, "reason": "n84_empty_source_leaves"}
    var nodes: Array = []
    for step in expanded:
        var leaf: Dictionary = Bt.action(step)
        if leaf.is_empty():
            return {"ok": false, "reason": "n84_unrepresentable_leaf"}
        nodes.append(leaf)
    var tree: Dictionary = Bt.sequence(nodes)
    if not Bt.validate(tree):
        return {"ok": false, "reason": "n84_invalid_compiled_tree"}
    return {"ok": true, "goal": "fulfill_delivery",
        "n80_score": float(scored["score"]), "personality_source": provenance,
        "n81_cost": int(goap["cost"]), "n81_actions": normalized,
        "ai_bt": tree, "n84_action": Bt.current_action(tree)}
