extends RefCounted
## N151 native colony founding: SOURCE commission into an actual N39
## ConstructionSite, not a free station, market, ship, cargo or household.
## No destination may be invented outside the ORIGINAL N4 directed registry.
const Commission = preload("res://scripts/sim/phase1/n151_native_colony_commission.gd")
const Locations = preload("res://scripts/sim/ships/native_location_resolver.gd")
const Catalog = preload("res://scripts/sim/ship_catalog.gd")
const N91 = preload("res://scripts/ported/n91_construction_executor.gd")

static func proposal(world: Dictionary, original: RefCounted, graph: RefCounted,
        faction: String, body_id: String, source: String, tick: int,
        multiplier: int, head_authorized: bool) -> Dictionary:
    if not head_authorized:
        return {"ok": false, "reason": "n151_head_colony_approval_required"}
    if tick < 1 or multiplier < 1 or original == null or graph == null:
        return {"ok": false, "reason": "n151_native_founding_context_missing"}
    var treasury: Dictionary = world.get("faction_treasuries", {})
    if not treasury.has(faction) or not world.get("markets", {}).has(source):
        return {"ok": false, "reason": "n151_real_sponsor_or_treasury_missing"}
    var station_id: String = str(world["markets"][source].get("owner", ""))
    var station: Dictionary = world.get("facilities", {}).get(station_id, {})
    if str(station.get("faction", "")) != faction or str(station.get("type", "")) != "station" or str(station.get("location", "")) != source:
        return {"ok": false, "reason": "n151_founding_without_real_home_station"}
    var body_record: Dictionary = original.body_by_id(body_id)
    if body_record.is_empty() or not world.get("bodies", {}).has(body_id):
        return {"ok": false, "reason": "n151_body_missing_from_frozen_world"}
    var body: Dictionary = body_record.get("value", {})
    if str(body.get("type", "")) != "planet":
        return {"ok": false, "reason": "n151_colony_requires_original_planet"}
    var raw_resources: Dictionary = world["bodies"][body_id].get("resources", {})
    if maxf(float(raw_resources.get("ore", 0.0)),
            maxf(float(raw_resources.get("ice", 0.0)),
                float(raw_resources.get("gas", 0.0)))) <= 0.0:
        return {"ok": false, "reason": "n151_source_colony_resource_missing"}
    for facility in world["facilities"].values():
        if str(facility.get("body_id", "")) == body_id:
            return {"ok": false, "reason": "n151_original_body_already_occupied"}
    var sites: Array = []
    for id in world.get("construction_sites", {}):
        var existing: Dictionary = world["construction_sites"][id]
        sites.append(existing)
        if str(existing.get("body_id", "")) == body_id and not bool(existing.get("completed", false)):
            return {"ok": false, "reason": "n151_existing_unfinished_colony_site"}
        if str(existing.get("faction_id", "")) == faction and existing.get("labor", {}).get("colony_source", null) != null:
            return {"ok": false, "reason": "n151_one_founding_expedition_per_faction"}
    var destination: String = body_id + "-colony"
    # The frozen WorldRegistry does not generate planet-colony nodes from
    # body names. Until the ORIGINAL nav graph knows the endpoint, STOP.
    var route: Dictionary = graph.shortest_path(source, destination)
    if not bool(route.get("reachable", false)) or not route.get("locations", []).has(destination):
        return {"ok": false, "reason": "n151_colony_location_not_in_original_navigation"}
    var same_system: String = str(body_record.get("system_id", ""))
    if str(original.body_by_id(str(station.get("body_id", ""))).get("system_id", "")) != same_system:
        # Interstellar expansion is source-supported only once a real
        # fleet route/transport capability has been demonstrated.
        return {"ok": false, "reason": "n151_remote_founding_executor_unverified"}
    var director: bool = world.get("research_directors", {}).has(faction)
    var settlers: int = 50 if director else Commission.SETTLERS
    if director and not world.get("research", {}).get(faction, []).has("orbital_habitats"):
        return {"ok": false, "reason": "n151_source_requires_orbital_habitats"}
    var count: int = 0
    for p in world["populations"].values():
        if str(p.get("faction", "")) == faction and str(p.get("location", "")) == source:
            count += int(p.get("count", 0))
    if count < settlers * 2:
        return {"ok": false, "reason": "n151_insufficient_real_settlers"}
    var market: Dictionary = world["markets"][source]
    var metals: float = float(market.get("supply", {}).get("metals", 0.0))
    if not is_finite(metals) or metals < float(Commission.CONSTRUCTION_PROGRESS_REQUIRED):
        return {"ok": false, "reason": "n151_original_metals_not_available"}
    # The original Rust N144 cost formula: three 200-unit shipments,
    # 10_000 CR each, 20_000 startup, 150 paid shifts at 1 CR,
    # and 80 CR per settler. No new money is charged on site spawn.
    var founding_cost: int = 3 * 10000 + 20000 + 150 + settlers * 80
    if int(treasury[faction]) - Commission.SUBSIDY_FLOOR < founding_cost:
        return {"ok": false, "reason": "n151_native_colony_budget_unavailable"}
    # Native N144 also requires a real passenger ship, solvent metal
    # carrier, engineer, and one feasible home-to-project expedition.
    # Existing ship rows and class specs are canonical: no proxy hull.
    var has_passengers: bool = false
    var has_materials: bool = false
    var has_engineer: bool = false
    var unit_price: float = float(market.get("prices", {}).get("metals", 0.0))
    var lot_cost: int = ceili(unit_price * 200.0) if is_finite(unit_price) and unit_price > 0.0 else 2147483647
    for raw in world.get("ships", {}).values():
        if not (raw is Dictionary) or str(raw.get("faction_id", "")) != faction:
            continue
        var ship: Dictionary = raw
        if float(ship.get("fuel", 0.0)) <= 0.0 or str(ship.get("location", "")).is_empty():
            continue
        var point: String = str(ship["location"])
        if point != source and not graph.shortest_path(point, source).get("reachable", false):
            continue
        var class_id: String = str(ship.get("class", ""))
        var spec: Dictionary = Catalog.spec(class_id)
        if spec.is_empty():
            continue
        has_passengers = has_passengers or int(spec.get("passenger_capacity", 0)) >= settlers
        has_materials = has_materials or (int(ship.get("cargo_capacity", 0)) >= 200 and lot_cost < 10000 and int(ship.get("credits", 0)) >= lot_cost)
        has_engineer = has_engineer or N91.capable(class_id, Catalog.CLASSES)
    if not has_passengers:
        return {"ok": false, "reason": "n151_no_original_passenger_ship"}
    if not has_materials:
        return {"ok": false, "reason": "n151_no_solvent_metals_carrier"}
    if not has_engineer:
        return {"ok": false, "reason": "n151_no_original_engineering_ship"}
    var sponsor_position: Vector2 = original.seed_universe_position(same_system)
    if not is_finite(sponsor_position.x) or not is_finite(sponsor_position.y):
        return {"ok": false, "reason": "n151_missing_original_orbit_center"}
    var radius: float = float(body.get("orbit_radius", -1.0))
    var angle: float = float(body.get("current_angle", NAN))
    if radius < 0.0 or not is_finite(radius) or not is_finite(angle):
        return {"ok": false, "reason": "n151_native_orbit_invalid"}
    var center: Vector2 = sponsor_position + Vector2(
        cos(deg_to_rad(angle)), sin(deg_to_rad(angle))) * radius
    var callback: Callable = func(position: Dictionary, site_id: String) -> Dictionary:
        var phase: float = deg_to_rad(float(Locations.initial_facility_angle(site_id)))
        return {"x": float(position["x"]) + cos(phase) * Locations.FACILITY_ORBIT_RADIUS,
            "y": float(position["y"]) + sin(phase) * Locations.FACILITY_ORBIT_RADIUS}
    var native_world: Dictionary = {
        "sites": sites,
        "bodies": {body_id: {"universe_center": {"x": center.x, "y": center.y}}},
        "treasuries": treasury.duplicate(true),
        "physical_distances": {source: {destination: int(route.get("distance", 0))}},
        "has_native_director": director}
    var plan: Dictionary = {"faction_id": faction, "source": source,
        "destination": destination,
        "body": {"body_id": body_id, "name": str(body.get("name", body_id))},
        "site_id": null, "quantity": settlers, "cost": founding_cost,
        "passenger": true}
    var staged: Dictionary = Commission.commission(plan, native_world,
        tick, multiplier, callback)
    if not staged.get("ok", false) or staged.get("kind", "") != "spawn_construction_site":
        return {"ok": false, "reason": str(staged.get("reason", "n151_source_commission_refused"))}
    var site: Dictionary = staged["site"].duplicate(true)
    # The original ConstructionLabor defaults are part of the source
    # project; they do not imply paid work, materials or settlement.
    site["labor"] = {"colony_source": source, "required": 150,
        "completed": 0, "last_shift": null, "station_order": null,
        "blocked_reason": null, "last_executor": null}
    return {"ok": true, "status": "N151_SOURCE_SITE_READY",
        "faction_id": faction, "body_id": body_id, "source": source,
        "site": site, "event": staged.get("event", {}).duplicate(true),
        "cost": 0, "destination": destination}

## Read-only readiness over original body IDs and actual source stations.
## This is NOT a colony-head authorization: it never calls N39 Apply.
static func scan(world: Dictionary, original: RefCounted, graph: RefCounted,
        tick: int, multiplier: int) -> Dictionary:
    if tick < 1 or original == null or graph == null or not (world.get("faction_treasuries") is Dictionary):
        return {"ok": false, "reason": "n151_source_world_not_ready"}
    var ready: Array = []
    var blocked: Array = []
    var factions: Array = world["faction_treasuries"].keys()
    factions.sort()
    var body_ids: Array = world.get("bodies", {}).keys()
    body_ids.sort()
    for faction in factions:
        var best_reason: String = "n151_no_planet_or_native_source_station"
        var found: bool = false
        for body_id in body_ids:
            var item: Dictionary = original.body_by_id(str(body_id))
            if str(item.get("value", {}).get("type", "")) != "planet":
                continue
            var source_ids: Array = world.get("markets", {}).keys()
            source_ids.sort()
            for source in source_ids:
                var owner_id: String = str(world["markets"][source].get("owner", ""))
                var sponsor: Dictionary = world.get("facilities", {}).get(owner_id, {})
                if str(sponsor.get("faction", "")) != str(faction) or str(sponsor.get("type", "")) != "station":
                    continue
                if str(original.body_by_id(str(sponsor.get("body_id", ""))).get("system_id", "")) != str(item.get("system_id", "")):
                    continue
                var plan: Dictionary = proposal(world, original, graph,
                    str(faction), str(body_id), str(source), tick,
                    multiplier, true)
                if plan.get("ok", false):
                    ready.append({"faction_id": str(faction),
                        "body_id": str(body_id),
                        "source": str(source),
                        "site_id": str(plan.get("site", {}).get("id", "")),
                        "status": "UNAUTHORIZED_PLAN_ONLY"})
                    found = true
                    break
                best_reason = str(plan.get("reason", "n151_colony_blocked"))
            if found:
                break
        if not found:
            blocked.append({"faction_id": str(faction), "reason": best_reason})
    return {"ok": true, "tick": tick, "ready": ready,
        "blocked": blocked, "applied": [],
        "status": "N151_SOURCE_NAV_AND_HEAD_REQUIRES_INTEGRATION"}
