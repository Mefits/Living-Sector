extends RefCounted
## Frozen Rust ship::behavior::resume_contract_bt, using existing N81
## GOAP and N153 native BT expansion; pure N104 source proposal only.
## Never AcceptContract, Buy existing picked-up cargo, fund escrow or
## move a ship. N84 saves the resulting tree on the ONE N39 ship.
const Goap = preload("res://scripts/sim/ships/ai/native_goap_planner.gd")
const Plans = preload("res://scripts/sim/phase1/n153_native_ship_bt_planning.gd")
const Bt = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")

static func _route(graph: RefCounted, origin: String, dest: String) -> Dictionary:
    if not graph.has_location(origin) or not graph.has_location(dest):
        return {}
    if origin == dest:
        return {"legs": [], "distance": 0.0}
    var found: Dictionary = graph.shortest_path(origin, dest)
    if not bool(found.get("reachable", false)):
        return {}
    var places: Array = found.get("locations", [])
    if places.size() < 2 or str(places[0]) != origin or str(places[-1]) != dest:
        return {}
    var legs: Array = []
    var distance: float = 0.0
    for i in range(1, places.size()):
        var a: String = str(places[i - 1])
        var to: String = str(places[i])
        var matched: Dictionary = {}
        for edge in graph.outgoing(a):
            if str(edge.get("to", "")) == to:
                matched = edge
                break
        if matched.is_empty() or not is_finite(
                float(matched.get("distance", -1.0))) or (
                float(matched.get("distance", -1.0)) <= 0.0):
            return {}
        var d: float = float(matched["distance"])
        distance += d
        if not is_finite(distance):
            return {}
        legs.append({"from": a, "to": to, "kind": "travel", "distance": d})
    return {"legs": legs, "distance": distance}

static func _routes(graph: RefCounted, start: String,
        source: String, dest: String) -> Dictionary:
    var result: Dictionary = {}
    for pair in [[start, source], [source, dest], [start, dest]]:
        var a: String = str(pair[0])
        var to: String = str(pair[1])
        var row: Dictionary = _route(graph, a, to)
        if not row.is_empty():
            result[a + "|" + to] = row["legs"]
    return result

static func propose(ship: Dictionary, contract: Dictionary,
        graph: RefCounted) -> Dictionary:
    var id: String = str(contract.get("id", ""))
    var status: String = str(contract.get("status", ""))
    var owner: String = str(contract.get("fulfiller_id", ""))
    var ship_id: String = str(ship.get("id", ""))
    var origin: String = str(ship.get("location", ""))
    var source: String = str(contract.get("source_location", ""))
    var dest: String = str(contract.get("destination_location", ""))
    var kind: String = str(contract.get("contract_type", ""))
    if graph == null or id.is_empty() or ship_id.is_empty() or (
            str(ship.get("active_contract_id", "")) != id or owner != ship_id or
            status not in ["accepted", "picked_up"] or
            origin.is_empty() or source.is_empty() or dest.is_empty()):
        return {"ok": false, "reason": "n104_no_active_original_obligation"}
    var source_kind: String = {
        "delivery": "Delivery", "construction": "Construction",
        "supply": "Supply", "courier": "Courier",
        "passenger": "Passenger", "crew_mission": "CrewMission"
    }.get(kind, "")
    if source_kind.is_empty():
        return {"ok": false, "reason": "n104_unknown_native_resume_catalog"}
    var cargo: Variant = ship.get("cargo", null)
    if not (cargo is Dictionary):
        return {"ok": false, "reason": "n104_no_physical_hold"}
    var good: String = str(contract.get("commodity", ""))
    var quantity: int = int(contract.get("quantity", -1))
    var onboard: int = int(cargo.get(good, 0))
    if quantity < 0 or onboard < 0:
        return {"ok": false, "reason": "n104_invalid_real_quantity"}
    if status == "picked_up" and source_kind not in ["Passenger", "CrewMission"] and (
            onboard < quantity):
        # A PickedUp receipt is NOT permission to manufacture missing
        # cargo. Preserve the contract for N38/N152 recovery.
        return {"ok": false, "reason": "n104_picked_up_cargo_not_physical"}
    var capacity: float = float(ship.get("fuel_capacity", 0.0))
    var fuel: float = float(ship.get("fuel", 0.0))
    if not is_finite(capacity) or capacity <= 0.0 or (
            not is_finite(fuel) or fuel < 0.0):
        return {"ok": false, "reason": "n104_invalid_original_fuel"}
    var routes: Dictionary = _routes(graph, origin, source, dest)
    if origin != dest and not routes.has(origin + "|" + dest):
        return {"ok": false, "reason": "n104_no_real_destination_route"}
    var request: Dictionary = Plans.resume_contract_request(
        origin, not str(ship.get("docked_at", "")).is_empty(),
        cargo, Goap.fuel_fraction_to_bucket(fuel / capacity), {
            "id": id, "contract_type": source_kind, "quantity": quantity,
            "commodity": good, "status": (
                "PickedUp" if status == "picked_up" else "Accepted"),
            "source_location": source, "destination_location": dest
        }, routes)
    if request.is_empty():
        return {"ok": false, "reason": "n104_native_n81_resume_request_rejected"}
    var initial: Dictionary = Goap.initial("Origin",
        Goap.fuel_fraction_to_bucket(fuel / capacity))
    initial.merge(request.get("initial", {}), true)
    var catalog: String = "crew_mission" if source_kind == "CrewMission" else (
        "passenger" if source_kind == "Passenger" else "delivery")
    var result: Dictionary = Goap.plan(initial, catalog,
        request.get("loc_map", {}), int(request.get("max_depth", 20)), 0)
    if result.is_empty() or not (result.get("actions") is Array) or (
            result["actions"].is_empty()):
        return {"ok": false, "reason": "n104_native_n81_resume_no_plan"}
    var actions: Array = []
    for item in result["actions"]:
        if not (item is Dictionary):
            return {"ok": false, "reason": "n104_corrupt_native_goap_leaf"}
        var spec: Dictionary = item.duplicate(true)
        spec["kind"] = str(spec.get("type", ""))
        spec.erase("type")
        if str(spec["kind"]).is_empty() or str(spec["kind"]) in [
                "AcceptContract", "Buy", "PickupCargo", "EmbarkPassengers"]:
            # This entry is for a previously PickedUp delivery; no
            # second pickup/accept/funding is possible.
            if status == "picked_up":
                return {"ok": false, "reason": "n104_resume_would_duplicate_pickup"}
        actions.append(spec)
    var expanded: Array = Plans.compile_plan_to_bt_actions(
        actions, request["loc_map"], routes, true)
    if expanded.is_empty():
        return {"ok": false, "reason": "n104_empty_source_resume_bt"}
    var nodes: Array = []
    for action in expanded:
        if not (action is Dictionary) or str(action.get(
                "kind", "")) == "AcceptContract":
            return {"ok": false, "reason": "n104_reaccepted_paid_job"}
        nodes.append(Bt.action(action))
    var tree: Dictionary = Bt.sequence(nodes)
    if not Bt.validate(tree):
        return {"ok": false, "reason": "n104_invalid_source_resume_bt"}
    return {"ok": true, "tree": tree, "goal": (
        "do_crew_mission" if source_kind == "CrewMission" else
        ("fulfill_passenger_transport" if source_kind == "Passenger" else
        ("fulfill_construction" if source_kind == "Construction" else
        "fulfill_delivery"))),
        "status": "N104_REAL_N81_GOAP_RESUME",
        "action_count": nodes.size(), "origin": origin,
        "destination": dest, "contract_id": id}
