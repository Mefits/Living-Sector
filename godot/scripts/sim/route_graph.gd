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

## This N4 graph is immutable between successful load_worlds() calls.
## N153 repeatedly asks about the same source/destination pair for
## different ships and source offers. Cache only detached finished routes;
## no state or monetary/profitability decisions are cached.
const MAX_PATH_CACHE: int = 4096
var _path_cache: Dictionary = {} # start -> {destination -> detached route}
var _path_cache_size: int = 0
# FIFO eviction avoids throwing away all hot routes on every 4097th query.
# Two typed FIFO columns avoid allocating a mutable pair Array per cache miss.
# Entries are scalar Strings, never World references.
var _path_cache_fifo_starts: Array[String] = []
var _path_cache_fifo_destinations: Array[String] = []
var _path_cache_fifo_head: int = 0
var _path_hits: int = 0
var _path_misses: int = 0

func path_cache_stats() -> Dictionary:
    return {"hits": _path_hits, "misses": _path_misses,
        "entries": _path_cache_size, "limit": MAX_PATH_CACHE}

func load_worlds(worlds: Array, native_seeded_db: bool = false) -> bool:
    var edges: Dictionary = {}
    var nodes: Dictionary = {}
    var count: int = 0
    # Per-origin positions preserve SQL upsert order without rescanning edges.
    var edge_positions: Dictionary = {}
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
                # Avoid allocating two temporary pair Arrays for every
                # seeded edge. The two SQL upserts retain their exact order.
                for direction in 2:
                    var origin: String = from_id if direction == 0 else to_id
                    var target: String = to_id if direction == 0 else from_id
                    if not edges.has(origin):
                        edges[origin] = []
                    if not edge_positions.has(origin):
                        edge_positions[origin] = {}
                    var positions: Dictionary = edge_positions[origin]
                    if positions.has(target):
                        var index: int = int(positions[target])
                        edges[origin][index]["distance"] = distance
                        edges[origin][index]["system_id"] = sid
                    else:
                        positions[target] = edges[origin].size()
                        edges[origin].append({
                            "to": target, "distance": distance, "system_id": sid})
                        count += 1
            else:
                # Source JSON is still directional: generic N59/N58
                # tests and callers must not infer the Rust DB migration.
                if not edges.has(from_id):
                    edges[from_id] = []
                # Raw N4 rejects duplicates (unlike native SQL upsert).
                # Reuse the per-origin membership index instead of scanning
                # every prior outgoing edge for each new route.
                if not edge_positions.has(from_id):
                    edge_positions[from_id] = {}
                var raw_positions: Dictionary = edge_positions[from_id]
                if raw_positions.has(to_id):
                    return false
                raw_positions[to_id] = edges[from_id].size()
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
            if not edge_positions.has(origin):
                edge_positions[origin] = {}
            var positions: Dictionary = edge_positions[origin]
            if positions.has(dest):
                continue # SQL INSERT OR IGNORE preserves explicit seed edge
            positions[dest] = edges[origin].size()
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
    # A failed load leaves the old immutable graph and its cache intact.
    # Clear the cache only after replacing the authoritative topology.
    _path_cache.clear()
    _path_cache_fifo_starts.clear()
    _path_cache_fifo_destinations.clear()
    _path_cache_fifo_head = 0
    _path_cache_size = 0
    _path_hits = 0
    _path_misses = 0
    return true

func edge_count() -> int:
    return _edge_count

func has_location(location: String) -> bool:
    return _nodes.has(location)

## Each N4 edge is a flat dictionary of scalar (String/float) values.
## Copy the outer roster and each row, not recursively duplicate the whole
## adjacency graph. Callers may mutate returned rows without touching N4.
## Do not return _edges[location] or a shallow outer Array duplicate: both
## would expose the authoritative edge dictionaries to callers.
func outgoing(location: String) -> Array:
    var source: Array = _edges.get(location, [])
    var detached: Array = []
    detached.resize(source.size())
    for i in range(source.size()):
        detached[i] = (source[i] as Dictionary).duplicate()
    return detached

## N4 route results contain only scalar metadata and a flat locations Array.
## Detach that Array explicitly rather than recursively deep-copying every
## string on each N153 cache hit. Neither caller nor cache owns the other's
## mutable container. Negative routes have no locations Array.
static func _detached_route(route: Dictionary) -> Dictionary:
    var copy: Dictionary = route.duplicate()
    if route.get("locations") is Array:
        copy["locations"] = (route["locations"] as Array).duplicate()
    return copy

## Cached results are returned as independent dictionaries so callers
## can never rewrite a later ship's deterministic route. Negative routes
## are cached too; successful graph reloads invalidate every cached pair.
func shortest_path(start: String, destination: String) -> Dictionary:
    var destinations: Dictionary = _path_cache.get(start, {})
    if destinations.has(destination):
        _path_hits += 1
        return _detached_route(destinations[destination])
    _path_misses += 1
    var result: Dictionary = _shortest_path_uncached(start, destination)
    if _path_cache_size >= MAX_PATH_CACHE:
        var old_start: String = _path_cache_fifo_starts[_path_cache_fifo_head]
        var old_destination: String = _path_cache_fifo_destinations[_path_cache_fifo_head]
        _path_cache_fifo_head += 1
        var old_destinations: Dictionary = _path_cache[old_start]
        old_destinations.erase(old_destination)
        if old_destinations.is_empty():
            _path_cache.erase(old_start)
        _path_cache_size -= 1
        # Compact occasionally: queue memory remains O(MAX_PATH_CACHE).
        if _path_cache_fifo_head >= MAX_PATH_CACHE:
            _path_cache_fifo_starts = _path_cache_fifo_starts.slice(_path_cache_fifo_head)
            _path_cache_fifo_destinations = _path_cache_fifo_destinations.slice(_path_cache_fifo_head)
            _path_cache_fifo_head = 0
    if not _path_cache.has(start):
        _path_cache[start] = {}
    _path_cache[start][destination] = _detached_route(result)
    _path_cache_fifo_starts.append(start)
    _path_cache_fifo_destinations.append(destination)
    _path_cache_size += 1
    return result

## Heap entries are immutable snapshots of a tentative best path. A changed
## distance/path pushes a new entry; stale entries are discarded on pop.
## Strict ordering is required for a heap. The original approximate tie\n## rule is non-transitive; ambiguous near-equal frontiers use the legacy scan.
static func _frontier_less(a: Dictionary, b: Dictionary) -> bool:
    var da: float = float(a["distance"])
    var db: float = float(b["distance"])
    return da < db or (da == db and str(a["path"]) < str(b["path"]))

static func _frontier_push(heap: Array, item: Dictionary) -> void:
    heap.append(item)
    var child: int = heap.size() - 1
    while child > 0:
        var parent: int = (child - 1) / 2
        if not _frontier_less(heap[child], heap[parent]):
            break
        var swap: Dictionary = heap[parent]
        heap[parent] = heap[child]
        heap[child] = swap
        child = parent

static func _frontier_pop(heap: Array) -> Dictionary:
    var first: Dictionary = heap[0]
    var last: Dictionary = heap.pop_back()
    if heap.is_empty():
        return first
    heap[0] = last
    var parent: int = 0
    while true:
        var left: int = parent * 2 + 1
        if left >= heap.size():
            break
        var right: int = left + 1
        var child: int = left
        if right < heap.size() and _frontier_less(heap[right], heap[left]):
            child = right
        if not _frontier_less(heap[child], heap[parent]):
            break
        var swap: Dictionary = heap[parent]
        heap[parent] = heap[child]
        heap[child] = swap
        parent = child
    return first

## Exact source selection semantics for non-transitive approximate-distance ties.
## Used only when the strict heap encounters distinct near-equal frontier costs.
func _shortest_path_legacy(start: String, destination: String) -> Dictionary:
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
            var distance: float = float(best[node])
            var key: String = str(paths[node])
            if current.is_empty() or distance < smallest or (is_equal_approx(distance, smallest) and key < path_key):
                current = str(node)
                smallest = distance
                path_key = key
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

## Source N4 directed Dijkstra and exact lexicographic tie-break retained.
func _shortest_path_uncached(start: String, destination: String) -> Dictionary:
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
    var frontier: Array = []
    _frontier_push(frontier, {"node": start, "distance": 0.0, "path": start})
    while not frontier.is_empty():
        var entry: Dictionary = _frontier_pop(frontier)
        # A strict heap is valid for exact distances, but the source N4
        # approximate tie-break is not transitive. Fall back to the source
        # linear scan when a distinct near-equal candidate is pending.
        if not frontier.is_empty():
            var popped_distance: float = float(entry["distance"])
            var next_distance: float = float(frontier[0]["distance"])
            if next_distance != popped_distance and is_equal_approx(next_distance, popped_distance):
                return _shortest_path_legacy(start, destination)
            if next_distance == popped_distance:
                for pending in frontier:
                    var pending_distance: float = float(pending["distance"])
                    if pending_distance != popped_distance and is_equal_approx(pending_distance, popped_distance):
                        return _shortest_path_legacy(start, destination)
        var current: String = str(entry["node"])
        if visited.has(current):
            continue
        # The heap can contain earlier tentative routes for the same node.
        if float(entry["distance"]) != float(best[current]) or str(entry["path"]) != str(paths[current]):
            continue
        var smallest: float = float(entry["distance"])
        var path_key: String = str(entry["path"])
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
            # Most relaxations lose on distance. Avoid allocating a full
            # lexicographic path string unless the distance can still win.
            # Keep is_equal_approx for the original Rust-port tie semantics.
            if best.has(target):
                var incumbent: float = float(best[target])
                if candidate > incumbent and not is_equal_approx(candidate, incumbent):
                    continue
            var candidate_path: String = path_key + "/" + target
            if not best.has(target) or candidate < float(best[target]) or (is_equal_approx(candidate, float(best[target])) and candidate_path < str(paths[target])):
                best[target] = candidate
                paths[target] = candidate_path
                previous[target] = current
                _frontier_push(frontier, {"node": target,
                    "distance": candidate, "path": candidate_path})
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
