extends RefCounted
## N61: bridge N58 read-only audit, N59 directed shortest path, and N60
## per-hop admission. Source travel_routes weights are NOT spatial distances
## or fuel costs, and planning NEVER moves or teleports any ship.
const GraphAudit = preload("res://scripts/sim/route_graph_audit.gd")
const Planner = preload("res://scripts/sim/directed_route_planner.gd")
const Admission = preload("res://scripts/sim/route_itinerary_admission.gd")
const MAX_COST: int = 4294967295

var _graph: RefCounted
var _locations: Array = []
var _routes: Array = []
var _ready: bool = false

## Source validation must finish before installation into a live engine.
## N59 currently models directed TRAVEL legs only. Gate transfer requires
## separate physical ship/gate rules, so gate_pairs are intentionally {}.
func load_native(seed: Dictionary, graph: RefCounted) -> bool:
    if not (seed.get("worlds", null) is Array) or graph == null:
        return false
    if not graph.has_method("snapshot") or not graph.has_method("outgoing"):
        return false
    var audit: Dictionary = GraphAudit.new().audit(seed["worlds"], graph)
    if not bool(audit.get("ok", false)):
        return false
    var snapshot: Dictionary = graph.snapshot()
    if not (snapshot.get("edges", null) is Array):
        return false
    var unique: Dictionary = {}
    var arcs: Array = []
    for world_value in seed["worlds"]:
        if not (world_value is Dictionary):
            return false
        var world: Dictionary = world_value
        for collection in ["facilities", "nav_sites"]:
            var items: Variant = world.get(collection, null)
            if not (items is Array):
                return false
            for value in items:
                if not (value is Dictionary):
                    return false
                var field: String = "location" if collection == "facilities" else "name"
                var key: String = str(value.get(field, ""))
                if not key.is_empty():
                    unique[key] = true
    for edge_value in snapshot["edges"]:
        if not (edge_value is Dictionary):
            return false
        var edge: Dictionary = edge_value
        var from_id: String = str(edge.get("from", ""))
        var to_id: String = str(edge.get("to", ""))
        var raw: Variant = edge.get("distance", null)
        if from_id.is_empty() or to_id.is_empty():
            return false
        if not (raw is int or raw is float) or not is_finite(float(raw)):
            return false
        var distance: float = float(raw)
        # Rust N59 planner uses exact positive u32 travel weights.
        # Fail closed on fractional, negative and oversized route weights.
        if distance < 1.0 or distance > float(MAX_COST) or float(int(distance)) != distance:
            return false
        unique[from_id] = true
        unique[to_id] = true
        arcs.append({"from": from_id, "to": to_id, "distance": int(distance)})
    var locations: Array = unique.keys()
    locations.sort()
    if locations.size() != int(snapshot.get("node_count", -1)):
        return false
    _graph = graph
    _locations = locations
    _routes = arcs
    _ready = true
    return true

func plan(origin: String, destination: String) -> Dictionary:
    if not _ready:
        return _fail("route_graph_not_bound")
    var result: Dictionary = Planner.new().plan(_locations, _routes, {},
        origin, destination)
    if not bool(result.get("ok", false)):
        return _fail("planner_" + str(result.get("error", "unreachable")))
    var legs: Array = result.get("legs", [])
    if legs.is_empty():
        return _fail("already_at_destination")
    var route: Array = [origin]
    for leg_value in legs:
        if not (leg_value is Dictionary):
            return _fail("malformed_planner_leg")
        var leg: Dictionary = leg_value
        if str(leg.get("kind", "")) != "travel":
            return _fail("gate_requires_separate_authority")
        if str(leg.get("from", "")) != str(route.back()):
            return _fail("discontinuous_planned_route")
        route.append(str(leg.get("to", "")))
    var admitted: Dictionary = Admission.new().admit(
        _graph, origin, destination, route, float(result["cost"]))
    if not bool(admitted.get("accepted", false)):
        return _fail("itinerary_" + str(admitted.get("reason", "invalid")))
    return _public_plan(admitted)

## Validate a caller-supplied existing itinerary *again* against current
## directed graph. The caller must reissue a continuation at each waypoint;
## there is NO hidden persistent autopilot that would be lost in N54 saves.
func next_hop(origin: String, supplied: Dictionary) -> Dictionary:
    if not _ready:
        return _fail("route_graph_not_bound")
    var endpoint: Variant = supplied.get("destination", null)
    var raw: Variant = supplied.get("locations", null)
    var distance: Variant = supplied.get("distance", null)
    if not (endpoint is String) or not (raw is Array):
        return _fail("malformed_itinerary")
    if not (distance is int or distance is float) or not is_finite(float(distance)):
        return _fail("invalid_itinerary_distance")
    var admitted: Dictionary = Admission.new().admit(_graph, origin,
        endpoint, raw, float(distance))
    if not bool(admitted.get("accepted", false)):
        return _fail("itinerary_" + str(admitted.get("reason", "invalid")))
    var route: Array = admitted["locations"]
    if route.size() < 2:
        return _fail("no_next_hop")
    var tail: Dictionary = {}
    if route.size() > 2:
        var remaining: Array = route.slice(1)
        var tail_admission: Dictionary = Admission.new().admit(
            _graph, str(remaining[0]), endpoint, remaining)
        if not bool(tail_admission.get("accepted", false)):
            return _fail("remaining_itinerary_invalid")
        tail = _public_plan(tail_admission)
    return {"ok": true, "next": str(route[1]),
        "remaining": tail, "remaining_hops": maxi(0, route.size() - 2)}

func is_ready() -> bool:
    return _ready

static func _public_plan(admitted: Dictionary) -> Dictionary:
    return {"ok": true, "origin": admitted["origin"],
        "destination": admitted["destination"],
        "locations": (admitted["locations"] as Array).duplicate(),
        "legs": (admitted["legs"] as Array).duplicate(true),
        "distance": float(admitted["distance"]),
        "hop_count": int(admitted["hop_count"])}

static func _fail(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
