extends RefCounted
## N58: read-only provenance audit for the directed native route graph.
## Does not infer reverse arcs, world-space coordinates, or game time.
## Accepts only the exact edge multiset from native travel_routes.
func audit(worlds: Array, graph: RefCounted) -> Dictionary:
	var errors: Array[String] = []
	var expected: Dictionary = {}
	var systems: Dictionary = {}
	var endpoints: Dictionary = {}
	for wi in range(worlds.size()):
		var world_value: Variant = worlds[wi]
		if not (world_value is Dictionary):
			errors.append("world_not_dictionary:%d" % wi)
			continue
		var world: Dictionary = world_value
		var system_value: Variant = world.get("system", null)
		if not (system_value is Dictionary):
			errors.append("invalid_system:%d" % wi)
			continue
		var sid_value: Variant = system_value.get("id", "")
		if not (sid_value is String) or sid_value.is_empty():
			errors.append("invalid_system_id:%d" % wi)
			continue
		var sid: String = sid_value
		if systems.has(sid):
			errors.append("duplicate_system:" + sid)
		systems[sid] = true
		for key in ["facilities", "nav_sites"]:
			var items: Variant = world.get(key, [])
			if not (items is Array):
				errors.append("invalid_collection:%s:%s" % [sid, key])
				continue
			for item in items:
				if not (item is Dictionary):
					errors.append("invalid_endpoint:%s:%s" % [sid, key])
					continue
				var field: String = "location" if key == "facilities" else "name"
				var loc: Variant = item.get(field, "")
				if loc is String and not loc.is_empty():
					endpoints[loc] = true
		var routes: Variant = world.get("travel_routes", [])
		if not (routes is Array):
			errors.append("invalid_routes:" + sid)
			continue
		for ri in range(routes.size()):
			var raw: Variant = routes[ri]
			if not (raw is Dictionary):
				errors.append("invalid_route:%s:%d" % [sid, ri])
				continue
			var origin: Variant = raw.get("from", "")
			var target: Variant = raw.get("to", "")
			var weight: Variant = raw.get("distance", null)
			if not (origin is String) or not (target is String) or origin.is_empty() or target.is_empty() or origin == target:
				errors.append("invalid_arc:%s:%d" % [sid, ri])
				continue
			if not (weight is int or weight is float) or not is_finite(float(weight)) or float(weight) <= 0.0:
				errors.append("invalid_weight:%s:%d" % [sid, ri])
				continue
			var key: String = origin + "\u001f" + target
			if expected.has(key):
				errors.append("duplicate_arc:" + origin + "->" + target)
			else:
				expected[key] = {"from": origin, "to": target, "distance": float(weight), "system_id": sid}
			endpoints[origin] = true
			endpoints[target] = true
	var snapshot: Dictionary = graph.snapshot()
	var actual: Variant = snapshot.get("edges", null)
	if not (actual is Array):
		errors.append("invalid_graph_snapshot")
	else:
		var seen: Dictionary = {}
		for edge_value in actual:
			if not (edge_value is Dictionary):
				errors.append("invalid_graph_edge")
				continue
			var edge: Dictionary = edge_value
			var origin: String = str(edge.get("from", ""))
			var target: String = str(edge.get("to", ""))
			var key: String = origin + "\u001f" + target
			if seen.has(key):
				errors.append("graph_duplicate_arc:" + origin + "->" + target)
			seen[key] = true
			if not expected.has(key):
				errors.append("unexpected_arc:" + origin + "->" + target)
				continue
			var reference: Dictionary = expected[key]
			var weight: Variant = edge.get("distance", null)
			if not (weight is int or weight is float) or not is_finite(float(weight)) or float(weight) != reference["distance"] or str(edge.get("system_id", "")) != reference["system_id"]:
				errors.append("arc_mismatch:" + origin + "->" + target)
		for key in expected:
			if not seen.has(key):
				var edge: Dictionary = expected[key]
				errors.append("missing_arc:" + edge["from"] + "->" + edge["to"])
	if int(snapshot.get("node_count", -1)) != endpoints.size():
		errors.append("node_count_mismatch")
	if int(snapshot.get("schema", -1)) != 1:
		errors.append("graph_schema_mismatch")
	errors.sort()
	return {"ok": errors.is_empty(), "errors": errors, "expected_arcs": expected.size(), "expected_nodes": endpoints.size()}
