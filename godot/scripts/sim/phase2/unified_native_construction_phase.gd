extends RefCounted
## Gate4: pure source N154 strategy / commission against the SAME N39 World.
## No invented station money, ship, technology, orbit or head approval.
const Strategy = preload("res://scripts/sim/phase1/n154_native_construction_strategy.gd")
const Commission = preload("res://scripts/sim/phase1/n154_native_construction_commission.gd")
const MarketRules = preload("res://scripts/port/n97_ship_market_rules.gd")
const Recipes = preload("res://scripts/sim/economy/native_recipes.gd")

static func context(world: Dictionary, sources: Dictionary, original: RefCounted,
        graph: RefCounted, authorized: String = "") -> Dictionary:
    if original == null or graph == null or not (world.get("construction_sites") is Dictionary):
        return {}
    if not (world.get("faction_treasuries") is Dictionary):
        return {}
    var facilities: Array = []
    var ids: Array = world["facilities"].keys()
    ids.sort()
    for fid in ids:
        var f: Dictionary = world["facilities"][fid]
        facilities.append({"id": str(fid), "faction_id": str(f["faction"]),
            "facility_type": str(f["type"]), "location_name": str(f["location"]),
            "body_id": str(f["body_id"])})
    var body_centers: Dictionary = {}
    var body_resources: Dictionary = {}
    for bid in world["bodies"]:
        var lookup: Dictionary = original.body_by_id(str(bid))
        if lookup.is_empty():
            continue
        var body: Dictionary = lookup.get("value", {})
        var radius: float = float(body.get("orbit_radius", -1.0))
        var angle: float = float(body.get("current_angle", 0.0))
        if radius < 0.0 or not is_finite(radius) or not is_finite(angle):
            continue
        var center: Vector2 = original.seed_universe_position(str(lookup["system_id"]))
        center += Vector2(cos(deg_to_rad(angle)), sin(deg_to_rad(angle))) * radius
        body_centers[bid] = {"x": center.x, "y": center.y}
        body_resources[bid] = world["bodies"][bid]["resources"].duplicate(true)
    var markets: Dictionary = {}
    var physical_distances: Dictionary = {}
    var locations: Array = world["markets"].keys()
    locations.sort()
    for loc in locations:
        var m: Dictionary = world["markets"][loc]
        var owner_id: String = str(m.get("owner", ""))
        if not world["facilities"].has(owner_id):
            return {}
        var owner: Dictionary = world["facilities"][owner_id]
        var permissions: Dictionary = {}
        var multipliers: Dictionary = {}
        for faction in world["faction_treasuries"]:
            var fid: String = str(faction)
            var owner_fid: String = str(owner["faction"])
            if not sources.has(fid) or not sources.has(owner_fid):
                return {}
            var policy: Dictionary = MarketRules.commerce_allowed({}, fid, owner_fid)
            var posture: Dictionary = MarketRules.posture({}, fid, owner_fid, 0)
            if not policy.get("ok", false) or not posture.get("ok", false):
                return {}
            var outlaw: bool = str(sources[fid].get("type", "")) == "outlaw"
            var market_outlaw: bool = str(sources[owner_fid].get("type", "")) == "outlaw"
            permissions[fid] = bool(policy["allowed"]) and (
                fid == owner_fid or not (outlaw or market_outlaw))
            multipliers[fid] = float(posture["multiplier"])
        markets[loc] = {"owner": str(owner["faction"]),
            "supply": m["supply"].duplicate(true),
            "prices": m["prices"].duplicate(true),
            "shortage_ticks": m.get("history", {}).get("shortage_ticks", {}).duplicate(true),
            "commerce_allowed": permissions,
            "buy_multiplier_by_faction": multipliers}
        var paths: Dictionary = {}
        for dest in locations:
            var path: Dictionary = graph.shortest_path(str(loc), str(dest))
            if path.get("reachable", false):
                var weighted: float = float(path.get("distance", -1.0))
                if weighted >= 0.0 and weighted <= 1000000.0 and weighted == floor(weighted):
                    paths[dest] = int(weighted)
        physical_distances[loc] = paths
    var sites: Array = []
    var site_ids: Array = world["construction_sites"].keys()
    site_ids.sort()
    for sid in site_ids:
        sites.append(world["construction_sites"][sid].duplicate(true))
    var contracts: Array = []
    for cid in world.get("construction_contracts", {}):
        if not world.get("contract_board", {}).get("contracts", {}).has(cid):
            return {}
        var c: Dictionary = world["contract_board"]["contracts"][cid].duplicate(true)
        var site_id: String = str(world["construction_contracts"][cid])
        if not world["construction_sites"].has(site_id):
            return {}
        # N104 uses physical Delivery type while Rust N154 evaluates a
        # construction mission. This is a READ-ONLY strategy projection;
        # don't modify the canonical N104 settlement type or wallet ID.
        c["contract_type"] = "construction"
        c["requestor_id"] = str(world["construction_sites"][site_id]["faction_id"])
        c["mission_category"] = Commission.PROJECT_TAG
        c["funding"] = {"reserved": c.get("reserved", 0)}
        contracts.append(c)
    var tech: Dictionary = {}
    for fid in world["faction_treasuries"]:
        tech[fid] = {}
        for id in world.get("research", {}).get(fid, []):
            tech[fid][id] = true
    var tiers: Dictionary = {}
    for fid in world["facilities"]:
        tiers[fid] = int(world["facilities"][fid].get("level", 1))
    # Source N154 fallback-input inspection is based on the REAL Rust
    # recipe catalogue, not an always-empty invented factory table.
    var recipes: Array = []
    for r in Recipes.TABLE:
        recipes.append({"facility_type": str(r["facility"]),
            "inputs": r["in"].duplicate(true), "outputs": r["out"].duplicate(true)})
    return {"markets": markets, "facilities": facilities,
        "sites": sites, "body_centers": body_centers,
        "body_resources": body_resources, "contracts": contracts,
        "physical_distances": physical_distances,
        "technologies": tech, "station_tiers": tiers,
        "commodity_base_prices": MarketRules.BASE_PRICE,
        "production_recipes": recipes, "has_director": true,
        "persistent_objectives": {}, "authorized_industry_goals": {},
        "executing": not authorized.is_empty(),
        "construction_authorizations": {authorized: true} if not authorized.is_empty() else {}}

static func observe(world: Dictionary, sources: Dictionary, original: RefCounted,
        graph: RefCounted, faction: String, tick: int) -> Dictionary:
    var ctx: Dictionary = context(world, sources, original, graph)
    if ctx.is_empty() or not sources.has(faction) or not world["faction_treasuries"].has(faction):
        return {"ok": false, "reason": "missing_native_construction_world"}
    var f: Dictionary = {"id": faction, "treasury": int(world["faction_treasuries"][faction]),
        "prefer_goals": sources[faction].get("personality", {}).get("prefer_goals", {}).duplicate(true)}
    return Strategy.evaluate_faction(ctx, f, tick)

## A verified N134 head decision must authorize this action. A mere
## read-only goal preview or manual ship GUI cannot call it with authority.
static func stage(world: Dictionary, sources: Dictionary, original: RefCounted,
        graph: RefCounted, faction: String, tick: int, multiplier: int,
        head_authorized: bool, preferred_goal: Dictionary = {}) -> Dictionary:
    if not head_authorized:
        return {"ok": false, "reason": "n134_head_authorization_required"}
    if tick < 1 or multiplier < 1 or not sources.has(faction) or not world.get("faction_treasuries", {}).has(faction):
        return {"ok": false, "reason": "invalid_native_construction_tick"}
    var ctx: Dictionary = context(world, sources, original, graph, faction)
    if ctx.is_empty():
        return {"ok": false, "reason": "missing_original_construction_context"}
    var f: Dictionary = {"id": faction, "treasury": int(world["faction_treasuries"][faction]),
        "prefer_goals": sources[faction].get("personality", {}).get("prefer_goals", {}).duplicate(true)}
    var evaluated: Dictionary = Strategy.evaluate_faction(ctx, f, tick)
    if not evaluated.get("ok", false):
        return evaluated
    var offer: Variant = evaluated.get("chosen", null)
    # Source N134's grant is for an EXACT shortage goal; original
    # Strategy.run_cycle must not accidentally build the first ready
    # project if the HeadDecision funded a different one.
    if not preferred_goal.is_empty():
        offer = null
        for candidate in evaluated.get("view", {}).get("offers", []):
            var goal: Dictionary = candidate.get("goal", {})
            if bool(candidate.get("ready", false)) and str(goal.get("destination", "")) == str(preferred_goal.get("destination", "")) and str(goal.get("commodity", "")) == str(preferred_goal.get("commodity", "")):
                offer = candidate
                break
    if not (offer is Dictionary) or not offer.get("ready", false):
        return {"ok": false, "reason": str(evaluated.get("view", {}).get("reason", "no_native_ready_site"))}
    var source: String = str(offer.get("source", ""))
    var destination: String = str(offer.get("goal", {}).get("destination", ""))
    if source.is_empty() or not ctx["physical_distances"].get(source, {}).has(destination):
        return {"ok": false, "reason": "source_graph_route_unreachable"}
    # Actual native body-center anchor; no fabricated district coordinate.
    var offset: Callable = func(center: Dictionary, _id: String) -> Dictionary:
        return center.duplicate(true)
    var staged: Dictionary = Commission.stage_commission(ctx, f, offer,
        tick, multiplier, offset)
    if staged.get("ok", false):
        staged["approved_goal"] = offer.get("goal", {}).duplicate(true)
        staged["status"] = "N154_AUTHORIZED_STAGED_NOT_APPLIED"
    return staged
