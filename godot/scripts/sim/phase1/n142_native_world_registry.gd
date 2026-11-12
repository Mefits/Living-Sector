extends RefCounted
## N142 — frozen Rust sim_core/world/registry.rs.
## Read-only physical topology used by economic strategies and local carrier
## eligibility. This is NOT the N59 gate-enabled ship pathfinder.
## No inferred reverse arcs, estimated map distances, or gate teleportation.
const U32_MAX: int = 4294967295
const SCHEMA: int = 1

var _loaded: bool = false
var _systems: Dictionary = {}
var _locations: Dictionary = {}
var _routes: Dictionary = {}
var _faction_ids: Array[String] = []
var _error: String = ""

func is_loaded() -> bool:
	return _loaded

func last_error() -> String:
	return _error

static func _strict_u32(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0 and int(value) <= U32_MAX

static func _valid_vec2(value: Variant) -> bool:
	if not (value is Array) or value.size() != 2:
		return false
	if typeof(value[0]) not in [TYPE_FLOAT, TYPE_INT] or typeof(value[1]) not in [TYPE_FLOAT, TYPE_INT]:
		return false
	return is_finite(float(value[0])) and is_finite(float(value[1]))

static func _valid_system(name: String, value: Variant) -> bool:
	if not (value is Dictionary):
		return false
	if name.is_empty() or str(value.get("name", "")) != name:
		return false
	if typeof(value.get("db_id")) != TYPE_INT:
		return false
	if not _valid_vec2(value.get("universe_offset")):
		return false
	var spectral = value.get("star_type", null)
	return spectral == null or spectral is String

static func _valid_location(name: String, value: Variant) -> bool:
	if not (value is Dictionary):
		return false
	if name.is_empty() or str(value.get("name", "")) != name:
		return false
	if typeof(value.get("db_id")) != TYPE_INT or typeof(value.get("celestial_body_id")) != TYPE_INT:
		return false
	return value.get("loc_type") is String

static func _validate(data: Dictionary) -> String:
	for key in ["systems", "locations", "routes", "faction_ids"]:
		if not data.has(key):
			return "missing_native_registry_field:" + key
	var systems = data["systems"]
	var locations = data["locations"]
	var routes = data["routes"]
	var factions = data["faction_ids"]
	if not (systems is Dictionary) or not (locations is Dictionary) or not (routes is Dictionary) or not (factions is Array):
		return "invalid_native_registry_collection"
	for name in systems:
		if not (name is String) or not _valid_system(name, systems[name]):
			return "invalid_system_metadata:" + str(name)
	for name in locations:
		if not (name is String) or not _valid_location(name, locations[name]):
			return "invalid_location_metadata:" + str(name)
	for origin in routes:
		if not (origin is String) or not (routes[origin] is Array):
			return "invalid_route_group:" + str(origin)
		# A native registry is an authoritative DB snapshot. Every origin and
		# destination must correspond to actual LocationInfo; do not create
		# missing nav sites from a graph edge as a workaround.
		if not locations.has(origin):
			return "unknown_route_origin:" + str(origin)
		for edge in routes[origin]:
			if not (edge is Dictionary):
				return "invalid_route_entry:" + str(origin)
			if not (edge.get("to") is String) or str(edge["to"]).is_empty():
				return "invalid_route_destination:" + str(origin)
			if not locations.has(str(edge["to"])):
				return "unknown_route_destination:" + str(edge["to"])
			if not _strict_u32(edge.get("distance")):
				return "invalid_u32_route_distance:" + str(origin)
		# No automatic deduplication: Rust travel_distance returns the
		# FIRST matching route if DB has repeated arcs.
	var faction_seen := {}
	for faction in factions:
		if not (faction is String) or str(faction).is_empty() or faction_seen.has(faction):
			return "invalid_faction_id"
		faction_seen[faction] = true
	return ""

func load_native_snapshot(data: Dictionary) -> bool:
	## A failed import leaves the PREVIOUS accepted snapshot unchanged,
	## never half-mutates the economy's shared topology reference.
	var failure := _validate(data)
	if failure != "":
		_error = failure
		return false
	_systems = data["systems"].duplicate(true)
	_locations = data["locations"].duplicate(true)
	_routes = data["routes"].duplicate(true)
	_faction_ids.clear()
	for faction in data["faction_ids"]:
		_faction_ids.append(str(faction))
	_loaded = true
	_error = ""
	return true

func system(name: String) -> Dictionary:
	return _systems.get(name, {}).duplicate(true) if _loaded else {}

func location(name: String) -> Dictionary:
	return _locations.get(name, {}).duplicate(true) if _loaded else {}

func faction_ids() -> Array[String]:
	return _faction_ids.duplicate()

func systems() -> Array[String]:
	var names: Array[String] = []
	if not _loaded:
		return names
	for name in _systems:
		names.append(str(name))
	names.sort()
	return names

func locations() -> Array[String]:
	var names: Array[String] = []
	if not _loaded:
		return names
	for name in _locations:
		names.append(str(name))
	names.sort()
	return names

func reachable_from(name: String) -> Array[Dictionary]:
	## Native WorldRegistry::reachable_from() returns [] if no outgoing.
	## Copy protects the trusted snapshot against planner mutation.
	var output: Array[Dictionary] = []
	if not _loaded:
		return output
	for route in _routes.get(name, []):
		output.append(route.duplicate(true))
	return output

func travel_distance(origin: String, destination: String) -> Dictionary:
	## Native WorldRegistry.travel_distance returns Option<u32> for the
	## FIRST exact directed edge, NOT a multihop path. It does not require
	## a location to have an entry in the registry if such an edge exists.
	if not _loaded:
		return _none("registry_unloaded")
	for edge in _routes.get(origin, []):
		if str(edge["to"]) == destination:
			return _some(int(edge["distance"]))
	return _none("no_direct_route")

static func _some(distance: int) -> Dictionary:
	return {"found": true, "distance": distance, "reason": ""}

static func _none(reason: String) -> Dictionary:
	return {"found": false, "distance": -1, "reason": reason}

static func _less(a: Array, b: Array) -> bool:
	## Rust BinaryHeap<Reverse<(cost:u32,location:String)>> order.
	return int(a[0]) < int(b[0]) or (int(a[0]) == int(b[0]) and str(a[1]) < str(b[1]))

static func _push(heap: Array, item: Array) -> void:
	heap.append(item)
	var idx := heap.size() - 1
	while idx > 0:
		var parent := (idx - 1) / 2
		if not _less(heap[idx], heap[parent]):
			break
		var old = heap[parent]
		heap[parent] = heap[idx]
		heap[idx] = old
		idx = parent

static func _pop(heap: Array) -> Array:
	var first: Array = heap[0]
	var last = heap.pop_back()
	if heap.is_empty():
		return first
	heap[0] = last
	var idx := 0
	while true:
		var left: int = idx * 2 + 1
		if left >= heap.size():
			break
		var right: int = left + 1
		var smallest: int = left
		if right < heap.size() and _less(heap[right], heap[left]):
			smallest = right
		if not _less(heap[smallest], heap[idx]):
			break
		var old = heap[smallest]
		heap[smallest] = heap[idx]
		heap[idx] = old
		idx = smallest
	return first

func shortest_distance(origin: String, destination: String) -> Dictionary:
	## Native WorldRegistry::shortest_distance is intentionally physical
	## travel ONLY, excluding any gate_pairs. Strategy uses conservative
	## corridor cost; actual ship BT/paid gate jumps use N59 and N108.
	## Rust returns Some(0) for same origin even if origin is unknown.
	if not _loaded:
		return _none("registry_unloaded")
	if origin == destination:
		return _some(0)
	if not _locations.has(origin) or not _locations.has(destination):
		return _none("unknown_location")
	var costs := {origin: 0}
	var heap: Array = []
	_push(heap, [0, origin])
	while not heap.is_empty():
		var row := _pop(heap)
		var cost: int = int(row[0])
		var name: String = str(row[1])
		if name == destination:
			return _some(cost)
		if cost > int(costs.get(name, U32_MAX)):
			continue
		for edge in _routes.get(name, []):
			var next: String = str(edge["to"])
			if not _locations.has(next):
				continue
			# Rust uses u32::saturating_add, and updates only on strictly
			# smaller cost; a saturated MAX path is NOT a valid discovery
			# when its current default is also MAX.
			var length: int = int(edge["distance"])
			var candidate: int = mini(U32_MAX, cost + length)
			if candidate < int(costs.get(next, U32_MAX)):
				costs[next] = candidate
				_push(heap, [candidate, next])
	return _none("no_physical_path")

func physical_distance_matrix(queries: Array) -> Dictionary:
	## Batch expected by N135 strategy/orders.rs while avoiding a
	## gate-enabled N59 path cost or guessed Euclidean/visual geometry.
	## Each query {from,to}; fail closed if any endpoints are unknown or
	## unreachable, so callers do not accidentally treat them as 0.
	if not _loaded:
		return {"ok": false, "reason": "registry_unloaded", "distances": {}}
	var result := {}
	for query in queries:
		if not (query is Dictionary) or not (query.get("from") is String) or not (query.get("to") is String):
			return {"ok": false, "reason": "invalid_distance_request", "distances": {}}
		var origin: String = str(query["from"])
		var destination: String = str(query["to"])
		var computed := shortest_distance(origin, destination)
		if not bool(computed.get("found", false)):
			return {"ok": false, "reason": "distance_unreachable:" + origin + ":" + destination,
				"distances": {}}
		if not result.has(origin):
			result[origin] = {}
		result[origin][destination] = computed["distance"]
	return {"ok": true, "reason": "", "distances": result}

func snapshot() -> Dictionary:
	## Canonical Dictionary copy — Rust registry is immutable Arc<WorldRegistry>.
	## Save adapters may serialize this native data; world seed is external.
	if not _loaded:
		return {}
	var result := {"schema": SCHEMA, "systems": {}, "locations": {}, "routes": {}, "faction_ids": _faction_ids.duplicate()}
	for name in systems():
		result["systems"][name] = _systems[name].duplicate(true)
	for name in locations():
		result["locations"][name] = _locations[name].duplicate(true)
	var froms: Array = _routes.keys()
	froms.sort()
	for origin in froms:
		result["routes"][origin] = _routes[origin].duplicate(true)
	return result

func restore_snapshot(value: Dictionary) -> bool:
	if int(value.get("schema", -1)) != SCHEMA:
		_error = "bad_registry_schema"
		return false
	return load_native_snapshot(value)
