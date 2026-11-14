extends RefCounted
## N4 raw JSON routes stay directed. But original Rust sim_db/seeder.rs
## inserts BOTH forward and reverse travel_routes into the active DB.
## Only the native-seeded mode below reconstructs those proven DB rows.
## Only native seeded mode includes spawner::chart_colony_routes SQL,
## strictly from original planet IDs and orbit radii, not render geometry.
const NativeChart = preload("res://scripts/sim/phase2/unified_n142_original_colony_chart.gd")
var _edges: Dictionary = {}
var _nodes: Dictionary = {}
var _edge_count: int = 0

func load_worlds(worlds: Array, native_seeded_db: bool = false) -> bool:
    var edges: Dictionary = {}
    var nodes: Dictionary = {}
    var count: int = 0
    for world in worlds:
        if not (world is Dictionary):
            return false
        var sid: String = str(world.get("system", {}).get("id", ""))
        if sid.is_empty():
            return false
        for facility in world.get("facilities", []):
            var location: String = str(facility.get("location", ""))
            if not location.is_empty():
                nodes[location] = true
        for site in world.get("nav_sites", []):
            var name: String = str(site.get("name", ""))
            if not name.is_empty():
                nodes[name] = true
        for route in world.get("travel_routes", []):
            if not (route is Dictionary):
                return false
            var from_id: String = str(route.get("from", ""))
            var to_id: String = str(route.get("to", ""))
            var distance_value: Variant = route.get("distance", null)
            if from_id.is_empty() or to_id.is_empty() or from_id == to_id:
                return false
            if not (distance_value is int or distance_value is float):
                return false
            var distance: float = float(distance_value)
            if not is_finite(distance) or distance <= 0.0:
                return false
            nodes[from_id] = true
            nodes[to_id] = true
            if native_seeded_db:
                # This is EXACTLY the Rust sim_db seeder's two INSERT ...
                # ON CONFLICT(from_location,to_location) DO UPDATE loops.
                # A repeated reverse edge is a DB upsert, not an extra arc.
                for pair in [[from_id, to_id], [to_id, from_id]]:
                    var origin: String = str(pair[0])
                    var target: String = str(pair[1])
                    if not edges.has(origin):
                        edges[origin] = []
                    var updated: bool = false
                    for existing in edges[origin]:
                        if str(existing["to"]) == target:
                            existing["distance"] = distance
                            existing["system_id"] = sid
                            updated = true
                            break
                    if not updated:
                        edges[origin].append({
                            "to": target, "distance": distance, "system_id": sid})
                        count += 1
            else:
                # Source JSON is still directional: generic N59/N58
                # tests and callers must not infer the Rust DB migration.
                if not edges.has(from_id):
                    edges[from_id] = []
                for existing in edges[from_id]:
                    if existing["to"] == to_id:
                        return false
                edges[from_id].append({
                    "to": to_id, "distance": distance, "system_id": sid})
                count += 1
    if native_seeded_db:
        # Rust startup: seeder::seed_all() THEN the explicit original
        # spawner::chart_colony_routes SQLite INSERT OR IGNORE transaction.
        # Raw mode remains exactly the original directed JSON graph.
        var chart: Dictionary = NativeChart.chart(worlds)
        if not chart.get("ok", false):
            return false
        for location in chart.get("charted", {}):
            nodes[location] = true
        for native in chart.get("edges", []):
            var origin: String = str(native["from"])
            var dest: String = str(native["to"])
            if not nodes.has(origin) or not nodes.has(dest):
                return false
            if not edges.has(origin):
                edges[origin] = []
            var exists: bool = false
            for active in edges[origin]:
                if str(active["to"]) == dest:
                    exists = true
                    break
            if exists:
                continue # SQL INSERT OR IGNORE preserves explicit seed edge
            edges[origin].append({"to": dest,
                "distance": float(native["distance"]),
                "system_id": str(native["system_id"])})
            count += 1
    for from_id in edges:
        edges[from_id].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
            return str(a["to"]) < str(b["to"]))
    _edges = edges
    _nodes = nodes
    _edge_count = count
    return true

func edge_count() -> int:
    return _edge_count

func has_location(location: String) -> bool:
    return _nodes.has(location)

func outgoing(location: String) -> Array:
    return _edges.get(location, []).duplicate(true)

func shortest_path(start: String, destination: String) -> Dictionary:
    if not _nodes.has(start) or not _nodes.has(destination):
        return {"reachable": false, "reason": "unknown_location"}
    if start == destination:
        return {"reachable": true, "locations": [start], "distance": 0.0}
    # Dijkstra with stable lexicographic tie-breaking. This is appropriate for
    # the small native graph; no scene nodes, guessed geometry or teleporting.
    var best: Dictionary = {start: 0.0}
    var paths: Dictionary = {start: start}
    var previous: Dictionary = {}
    var visited: Dictionary = {}
    while true:
        var current: String = ""
        var smallest: float = INF
        var path_key: String = ""
        for node in best:
            if visited.has(node):
                continue
            var candidate: float = float(best[node])
            var candidate_path: String = str(paths[node])
            if current.is_empty() or candidate < smallest or (is_equal_approx(candidate, smallest) and candidate_path < path_key):
                current = str(node)
                smallest = candidate
                path_key = candidate_path
        if current.is_empty():
            break
        if current == destination:
            var route: Array[String] = [destination]
            var cursor: String = destination
            while cursor != start:
                cursor = str(previous[cursor])
                route.push_front(cursor)
            return {"reachable": true, "locations": route, "distance": smallest}
        visited[current] = true
        for edge in _edges.get(current, []):
            var target: String = str(edge["to"])
            if visited.has(target):
                continue
            var candidate: float = smallest + float(edge["distance"])
            var candidate_path: String = path_key + "/" + target
            if not best.has(target) or candidate < float(best[target]) or (is_equal_approx(candidate, float(best[target])) and candidate_path < str(paths[target])):
                best[target] = candidate
                paths[target] = candidate_path
                previous[target] = current
    return {"reachable": false, "reason": "no_directed_path"}

func snapshot() -> Dictionary:
    var result: Array = []
    var origins: Array = _edges.keys()
    origins.sort()
    for origin in origins:
        for edge in _edges[origin]:
            result.append({"from": origin, "to": edge["to"],
                "distance": edge["distance"], "system_id": edge["system_id"]})
    return {"schema": 1, "edges": result, "node_count": _nodes.size()}
