extends RefCounted
## N63: durable explicit *intent* for a native directed itinerary.
## This does not move ships. N64 may dispatch one physical N14 leg per tick.
## No hidden autopilot or materialized commodities; source N60 admission.
const Admission = preload("res://scripts/sim/route_itinerary_admission.gd")
const MAX_INTENTS: int = 100000
var _entries: Dictionary = {}
var _request_ids: Dictionary = {}

func register(ship_id: String, operation_id: String, planned: Dictionary,
        graph: RefCounted, ships: Dictionary) -> Dictionary:
    if ship_id.is_empty() or operation_id.is_empty() or operation_id.length() > 160:
        return _fail("invalid_command_identity")
    if not _valid_graph(graph) or not ships.has(ship_id) or _entries.size() >= MAX_INTENTS:
        return _fail("invalid_ship_or_capacity")
    var origin: String = str((ships[ship_id] as Dictionary).get("location", ""))
    if origin.is_empty() or not (ships[ship_id].get("transit", {}) as Dictionary).is_empty():
        return _fail("ship_in_transit")
    var admitted: Dictionary = _admit_plan(planned, origin, graph)
    if not bool(admitted.get("accepted", false)):
        return _fail(str(admitted.get("reason", "invalid_plan")))
    if _request_ids.has(operation_id):
        var previous: String = str(_request_ids[operation_id])
        if previous == ship_id and _entries.has(ship_id):
            var old: Dictionary = _entries[ship_id]
            if old.get("locations", []) == admitted["locations"] and is_equal_approx(float(old.get("distance", -1.0)), float(admitted["distance"])):
                return {"ok": true, "duplicate": true, "entry": old.duplicate(true)}
        return _fail("reused_operation_id")
    if _entries.has(ship_id):
        return _fail("existing_intent")
    var entry: Dictionary = {
        "ship_id": ship_id, "operation_id": operation_id,
        "locations": (admitted["locations"] as Array).duplicate(),
        "distance": float(admitted["distance"]),
        "index": 0, "status": "ready"
    }
    _entries[ship_id] = entry
    _request_ids[operation_id] = ship_id
    return {"ok": true, "duplicate": false, "entry": entry.duplicate(true)}

func command_for_next_leg(ship_id: String, ships: Dictionary,
        graph: RefCounted) -> Dictionary:
    if not _entries.has(ship_id) or not ships.has(ship_id) or not _valid_graph(graph):
        return _fail("unknown_ship_or_intent")
    var entry: Dictionary = _entries[ship_id]
    if entry.get("status", "") != "ready":
        return _fail("not_ready")
    var index: int = int(entry["index"])
    var locations: Array = entry["locations"]
    if index < 0 or index >= locations.size() - 1:
        return _fail("no_next_leg")
    var ship: Dictionary = ships[ship_id]
    if str(ship.get("location", "")) != str(locations[index]) or not (ship.get("transit", {}) as Dictionary).is_empty():
        return _fail("ship_not_at_waypoint")
    var remaining: Array = locations.slice(index)
    var admitted: Dictionary = Admission.new().admit(graph, str(remaining[0]),
        str(locations[locations.size()-1]), remaining)
    if not bool(admitted.get("accepted", false)):
        return _fail("stale_native_route")
    return {"ok": true, "next": str(locations[index+1]), "remaining": remaining,
        "distance": float(admitted["distance"]), "index": index}

## Called ONLY after physical N14 departure succeeded. Verify real transit.
func confirm_departure(ship_id: String, ships: Dictionary) -> bool:
    if not _entries.has(ship_id) or not ships.has(ship_id):
        return false
    var entry: Dictionary = _entries[ship_id]
    if str(entry.get("status", "")) != "ready":
        return false
    var i: int = int(entry["index"])
    var places: Array = entry["locations"]
    if i < 0 or i+1 >= places.size():
        return false
    var ship: Dictionary = ships[ship_id]
    var flight: Variant = ship.get("transit", null)
    if not (flight is Dictionary):
        return false
    if str(flight.get("from", "")) != str(places[i]) or str(flight.get("to", "")) != str(places[i+1]):
        return false
    entry["status"] = "flying"
    return true

## Called after N14 arrival and N21 dock state reconciliation, exactly once.
func confirm_arrival(ship_id: String, ships: Dictionary) -> bool:
    if not _entries.has(ship_id) or not ships.has(ship_id):
        return false
    var entry: Dictionary = _entries[ship_id]
    if str(entry.get("status", "")) != "flying":
        return false
    var i: int = int(entry["index"])
    var places: Array = entry["locations"]
    var ship: Dictionary = ships[ship_id]
    if i < 0 or i+1 >= places.size() or str(ship.get("location", "")) != str(places[i+1]):
        return false
    if not (ship.get("transit", {}) as Dictionary).is_empty():
        return false
    entry["index"] = i+1
    entry["status"] = "done" if i+2 >= places.size() else "ready"
    return true

func entry_for(ship_id: String) -> Dictionary:
    return (_entries.get(ship_id, {}) as Dictionary).duplicate(true)

func snapshot() -> Array:
    var ids: Array = _entries.keys()
    ids.sort()
    var records: Array = []
    for id in ids:
        records.append((_entries[id] as Dictionary).duplicate(true))
    return records

## Atomic complete rebuild: exact phase/physical location and directed seed
## graph must agree, no reinitializing arrivals, fuel or cargo.
func restore(records: Array, ships: Dictionary, graph: RefCounted) -> bool:
    if not _valid_graph(graph) or records.size() > MAX_INTENTS:
        return false
    var new_entries: Dictionary = {}
    var new_ops: Dictionary = {}
    for value in records:
        if not (value is Dictionary):
            return false
        var entry: Dictionary = value
        var id: String = str(entry.get("ship_id", ""))
        var op: String = str(entry.get("operation_id", ""))
        if id.is_empty() or op.is_empty() or new_entries.has(id) or new_ops.has(op) or not ships.has(id):
            return false
        var places: Variant = entry.get("locations", null)
        var index_value: Variant = entry.get("index", null)
        var dist_value: Variant = entry.get("distance", null)
        if not (places is Array) or typeof(index_value) != TYPE_INT or not (dist_value is float or dist_value is int):
            return false
        var idx: int = int(index_value)
        if idx < 0 or idx >= places.size() or not is_finite(float(dist_value)) or float(dist_value) <= 0.0:
            return false
        var first: String = str(places[0])
        var last: String = str(places[places.size()-1])
        var admission: Dictionary = Admission.new().admit(graph, first, last, places, float(dist_value))
        if not bool(admission.get("accepted", false)):
            return false
        var state: String = str(entry.get("status", ""))
        var ship: Dictionary = ships[id]
        var flight: Variant = ship.get("transit", null)
        if not (flight is Dictionary):
            return false
        if state == "ready":
            if idx >= places.size()-1 or str(ship.get("location", "")) != str(places[idx]) or not flight.is_empty():
                return false
        elif state == "flying":
            if idx >= places.size()-1 or str(flight.get("from", "")) != str(places[idx]) or str(flight.get("to", "")) != str(places[idx+1]) or not str(ship.get("location", "")).is_empty():
                return false
        elif state == "done":
            if idx != places.size()-1 or str(ship.get("location", "")) != str(last) or not flight.is_empty():
                return false
        else:
            return false
        new_entries[id] = {"ship_id": id, "operation_id": op,
            "locations": (places as Array).duplicate(),
            "distance": float(admission["distance"]), "index": idx, "status": state}
        new_ops[op] = id
    _entries = new_entries
    _request_ids = new_ops
    return true

static func _admit_plan(plan: Dictionary, origin: String, graph: RefCounted) -> Dictionary:
    var raw: Variant = plan.get("locations", null)
    var goal: Variant = plan.get("destination", null)
    var distance: Variant = plan.get("distance", null)
    if not (raw is Array) or not (goal is String) or not (distance is float or distance is int):
        return {"accepted": false, "reason": "bad_plan"}
    return Admission.new().admit(graph, origin, str(goal), raw, float(distance))

static func _valid_graph(graph: RefCounted) -> bool:
    return graph != null and graph.has_method("has_location") and graph.has_method("outgoing")

static func _fail(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
