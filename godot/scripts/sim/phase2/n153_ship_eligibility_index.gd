extends RefCounted
## Per-propose N153 index. Rebuilt after every World mutation, tick and N38 load.
## No alternate Dijkstra; N4 remains the sole directed route authority.
const MarketRules = preload("res://scripts/port/n97_ship_market_rules.gd")

static func ship_ids(world: Dictionary) -> Array:
    var ids: Array = world["ships"].keys()
    ids.sort()
    return ids

static func offer_ids(contracts: Dictionary) -> Array:
    var ids: Array = []
    for id in contracts:
        var c: Dictionary = contracts[id]
        if str(c.get("status", "")) == "posted" and str(c.get("contract_type", "")) == "delivery":
            ids.append(id)
    ids.sort()
    return ids

static func posture(cache: Dictionary, ship_faction: String, seller_faction: String, reputation: int) -> Dictionary:
    var ship_cache: Dictionary = cache.get(ship_faction, {})
    var seller_cache: Dictionary = ship_cache.get(seller_faction, {})
    if not seller_cache.has(reputation):
        seller_cache[reputation] = MarketRules.posture({}, ship_faction, seller_faction, reputation)
        ship_cache[seller_faction] = seller_cache
        cache[ship_faction] = ship_cache
    return seller_cache[reputation]

## A proposal-scoped index shared only by offers with identical endpoints.
## The caller discards roots after propose(); no World/graph alias is stored.
static func offer_route_index(roots: Dictionary, source: String, destination: String) -> Dictionary:
    if not roots.has(source):
        roots[source] = {}
    var destinations: Dictionary = roots[source]
    if not destinations.has(destination):
        destinations[destination] = {}
    return destinations[destination]

static func legs(cache: Dictionary, here: String, source: String, dest: String,
        graph: RefCounted, positions: Dictionary, detach: bool = true,
        shared: Dictionary = {}) -> Dictionary:
    # Cache only per-contract origin geometry, not inter-call paths.
    if cache.has(here):
        return _detached_legs(cache[here]) if detach else cache[here]
    var result: Dictionary = {}
    if not _graph_has_location(shared, graph, source) or not _graph_has_location(shared, graph, dest) or not _graph_has_location(shared, graph, here):
        result = {"error": "native_route_endpoint_unmapped"}
    else:
        # Integer cache key cannot collide with a ship location (String).
        # Source->destination is invariant for every ship in this one
        # proposal; preserve the original inbound-then-outbound ordering
        # for the first lookup and never persist this across ticks/N38.
        var inbound: Dictionary = _inbound_path(shared, graph, here, source)
        var outbound: Dictionary = {}
        if cache.has(0):
            outbound = cache[0]
        else:
            outbound = graph.shortest_path(source, dest)
            cache[0] = outbound
        if not inbound.get("reachable", false) or not outbound.get("reachable", false):
            result = {"error": "unreachable_directed_route"}
        elif not _has_position(shared, positions, here) or not _has_position(shared, positions, source) or not _has_position(shared, positions, dest):
            result = {"error": "missing_real_world_position"}
        else:
            # The source->destination geometry is identical for all ships
            # bidding on this offer. Cache detached scalar leg rows, not
            # World positions, and append them in the original inbound-first
            # order. Each here-location receives its own steps Array.
            var steps: Array = _inbound_steps(shared, here, source,
                inbound["locations"], positions).duplicate()
            if not cache.has(1):
                cache[1] = _geometry_steps(outbound["locations"], positions)
            # The assembled steps stay private to this proposal's cache.
            # No external caller receives them without _detached_legs();
            # reusing immutable scalar rows avoids one dictionary copy per
            # outbound edge for every distinct bidder origin.
            steps.append_array(cache[1] as Array)
            result = {"inbound": inbound["locations"],
                "outbound": outbound["locations"], "steps": steps}
    cache[here] = result
    return _detached_legs(result) if detach else result

## Shared only within one synchronous N153 propose(). Cache endpoint presence,
## inbound directed routes and their scalar geometry across offers with
## different destinations. No graph/position version survives this call.
static func _graph_has_location(shared: Dictionary, graph: RefCounted,
        location: String) -> bool:
    var present: Dictionary = shared.get("graph_presence", {})
    if not present.has(location):
        present[location] = graph.has_location(location)
        shared["graph_presence"] = present
    return bool(present[location])

static func _has_position(shared: Dictionary, positions: Dictionary,
        location: String) -> bool:
    var present: Dictionary = shared.get("position_presence", {})
    if not present.has(location):
        present[location] = positions.has(location)
        shared["position_presence"] = present
    return bool(present[location])

static func _inbound_path(shared: Dictionary, graph: RefCounted,
        here: String, source: String) -> Dictionary:
    var routes: Dictionary = shared.get("inbound_routes", {})
    var by_source: Dictionary = routes.get(source, {})
    if not by_source.has(here):
        by_source[here] = graph.shortest_path(here, source)
        routes[source] = by_source
        shared["inbound_routes"] = routes
    return by_source[here]

static func _inbound_steps(shared: Dictionary, here: String, source: String,
        path: Array, positions: Dictionary) -> Array:
    var geometry: Dictionary = shared.get("inbound_geometry", {})
    var by_source: Dictionary = geometry.get(source, {})
    if not by_source.has(here):
        by_source[here] = _geometry_steps(path, positions)
        geometry[source] = by_source
        shared["inbound_geometry"] = geometry
    return by_source[here]

## A ship's fuel/cargo decision may inspect or modify its returned leg rows.
## The proposal cache owns its arrays; never expose them to another bidder.
## Rows are flat scalar dictionaries, so bounded one-level detachment is
## sufficient and avoids recursively copying immutable location strings.
static func _detached_legs(owned: Dictionary) -> Dictionary:
    var result: Dictionary = owned.duplicate()
    if owned.has("inbound"):
        result["inbound"] = (owned["inbound"] as Array).duplicate()
    if owned.has("outbound"):
        result["outbound"] = (owned["outbound"] as Array).duplicate()
    if owned.has("steps"):
        result["steps"] = _detach_step_rows(owned["steps"] as Array)
    return result

## Every geometry row contains only scalar values (bool and float).
## Duplicate the Array and each row, but never recurse into immutable values.
static func _detach_step_rows(source_steps: Array) -> Array:
    var steps: Array = []
    steps.resize(source_steps.size())
    for i in range(source_steps.size()):
        steps[i] = (source_steps[i] as Dictionary).duplicate()
    return steps

## N80's location resolver is read-only within one dispatch. Never
## persist the mapping across new World positions or an N38 restore.
static func system_for(cache: Dictionary, location: String, resolver: RefCounted) -> String:
    if not cache.has(location):
        cache[location] = resolver.system_for_location(location)
    return str(cache[location])

## Pure scalar projection: no mutable World/position alias escapes this helper.
## Preserve missing-position sentinel and the source leg iteration order.
static func _geometry_steps(path: Array, positions: Dictionary) -> Array:
    var steps: Array = []
    for i in range(1, path.size()):
        var from_id: String = str(path[i - 1])
        var to_id: String = str(path[i])
        var present: bool = positions.has(from_id) and positions.has(to_id)
        var distance: float = -1.0
        if present:
            var a: Vector2 = positions[from_id]
            var b: Vector2 = positions[to_id]
            distance = a.distance_to(b)
        steps.append({"present": present, "distance": distance})
    return steps
