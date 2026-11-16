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
        graph: RefCounted, positions: Dictionary) -> Dictionary:
    # Cache only per-contract origin geometry, not inter-call paths.
    if cache.has(here):
        return cache[here]
    var result: Dictionary = {}
    if not graph.has_location(source) or not graph.has_location(dest) or not graph.has_location(here):
        result = {"error": "native_route_endpoint_unmapped"}
    else:
        # Integer cache key cannot collide with a ship location (String).
        # Source->destination is invariant for every ship in this one
        # proposal; preserve the original inbound-then-outbound ordering
        # for the first lookup and never persist this across ticks/N38.
        var inbound: Dictionary = graph.shortest_path(here, source)
        var outbound: Dictionary = {}
        if cache.has(0):
            outbound = cache[0]
        else:
            outbound = graph.shortest_path(source, dest)
            cache[0] = outbound
        if not inbound.get("reachable", false) or not outbound.get("reachable", false):
            result = {"error": "unreachable_directed_route"}
        elif not positions.has(here) or not positions.has(source) or not positions.has(dest):
            result = {"error": "missing_real_world_position"}
        else:
            var steps: Array = []
            for path in [inbound["locations"], outbound["locations"]]:
                for i in range(1, path.size()):
                    var from_id: String = str(path[i - 1])
                    var to_id: String = str(path[i])
                    var present: bool = positions.has(from_id) and positions.has(to_id)
                    var distance: float = -1.0
                    if present:
                        var a: Vector2 = positions[from_id]
                        var b: Vector2 = positions[to_id]
                        distance = a.distance_to(b)
                    # Do NOT change original error priority: fuel-class is
                    # checked before per-leg missing/invalid geometry.
                    steps.append({"present": present, "distance": distance})
            result = {"inbound": inbound["locations"],
                "outbound": outbound["locations"], "steps": steps}
    cache[here] = result
    return result

## N80's location resolver is read-only within one dispatch. Never
## persist the mapping across new World positions or an N38 restore.
static func system_for(cache: Dictionary, location: String, resolver: RefCounted) -> String:
    if not cache.has(location):
        cache[location] = resolver.system_for_location(location)
    return str(cache[location])
