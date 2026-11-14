extends RefCounted
## N151 source: native/crates/sim_server/src/engine/colony.rs::prepare_docks.
## One empty temporary construction_dock and ONE zero-resident household
## per genuinely approved site. Neither is a market or a finished station.
## This adapter only PROPOSES; the ONE N39 World/N9 Ledger commits atomically.
const DOCK_TYPE: String = "construction_dock"
const DOCK_CAPACITY: int = 4

static func _fail(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}

static func _slug(label: String) -> String:
    # Rust name.to_lowercase().replace(non-alphanumeric, "-").
    # Godot RegEx accepts the Unicode letter/number classes.
    var regex := RegEx.new()
    if regex.compile("[^\\p{L}\\p{N}]") != OK:
        return ""
    return regex.sub(label.to_lower(), "-", true)

static func _dock_identity(site: Dictionary) -> Dictionary:
    var location: String = str(site.get("location_name", ""))
    var name: String = str(site.get("name", ""))
    var slug: String = _slug(name)
    if location.is_empty() or slug.is_empty():
        return {}
    var label: String = "Residents " + location
    return {"facility_id": "facility-" + location + "-" + slug,
        "population_id": "pop-" + label.to_lower().replace(" ", "-"),
        "label": label}

## Rust creates these actors from its existing approved ConstructionSite,
## not from a planet proposal or an unverified player-supplied order.
static func stage(world: Dictionary, tick: int, graph: RefCounted) -> Dictionary:
    if tick < 1 or graph == null or not (world.get("construction_sites") is Dictionary
            and world.get("construction_receipts") is Dictionary
            and world.get("facilities") is Dictionary
            and world.get("populations") is Dictionary
            and world.get("markets") is Dictionary):
        return _fail("n151_missing_single_world")
    var staged: Dictionary = world.duplicate(true)
    var created: Array = []
    var sites: Array = staged["construction_sites"].keys()
    sites.sort()
    for site_id in sites:
        var site: Dictionary = staged["construction_sites"][site_id]
        var labor: Variant = site.get("labor", {})
        if not (labor is Dictionary) or labor.get("colony_source", null) == null or bool(site.get("completed", false)):
            continue
        var location: String = str(site.get("location_name", ""))
        var sponsor: String = str(labor.get("colony_source", ""))
        var faction: String = str(site.get("faction_id", ""))
        var body: String = str(site.get("body_id", ""))
        var approved_id: String = "n151_colony_approved:" + str(site_id)
        var approved: Dictionary = staged["construction_receipts"].get(approved_id, {})
        if location != body + "-colony" or sponsor.is_empty() or faction.is_empty() or not graph.has_location(location) or not bool(graph.shortest_path(sponsor, location).get("reachable", false)):
            return _fail("n151_unregistered_colony_site_or_path")
        if str(approved.get("kind", "")) != "colony_approved" or str(approved.get("site_id", "")) != str(site_id) or str(approved.get("destination_location", "")) != location or str(approved.get("faction_id", "")) != faction:
            return _fail("n151_unapproved_colony_dock")
        if not staged["markets"].has(sponsor) or staged["markets"].has(location):
            return _fail("n151_colony_dock_not_empty_marketless_site")
        var has_facility: bool = false
        for old in staged["facilities"].values():
            if str(old.get("location", "")) == location:
                has_facility = true
                break
        # Native prepare_docks skips sites that already have a facility.
        # Existing receipt must not be replayed or multiplied.
        var receipt_id: String = "n151_colony_dock:" + str(site_id)
        if has_facility:
            if not staged["construction_receipts"].has(receipt_id):
                return _fail("n151_existing_facility_without_dock_proof")
            continue
        if staged["construction_receipts"].has(receipt_id):
            return _fail("n151_replayed_temporary_colony_dock")
        var ids: Dictionary = _dock_identity(site)
        if ids.is_empty():
            return _fail("n151_invalid_original_colony_names")
        var fid: String = str(ids["facility_id"])
        var pid: String = str(ids["population_id"])
        if staged["facilities"].has(fid) or staged["populations"].has(pid):
            return _fail("n151_duplicate_original_dock_or_household")
        var db_id: int = int(staged.get("construction_next_db_id", 0))
        if db_id >= 0 or db_id <= -9223372036854775807:
            return _fail("n151_invalid_native_db_allocator")
        # Negative temporary DB id is reserved from THE SAME N154 allocator.
        # No funds enter these zero-valued owner wallets until a real N9 Apply.
        staged["construction_next_db_id"] = db_id - 1
        staged["facilities"][fid] = {
            "type": DOCK_TYPE, "faction": faction, "location": location,
            "body_id": body, "name": str(site["name"]),
            "credits": 0, "crew_count": 0, "docking_capacity": DOCK_CAPACITY,
            "level": 1, "xp": 0, "abandoned": false,
            "condition": 1.0, "reputation": 50,
            "reserves": {}, "morale": 80.0,
            "fitting_output_mult": 1.0, "fitting_batches_bonus": 0,
            "native_db_id": db_id, "construction_source_site_id": str(site_id)}
        staged["populations"][pid] = {
            "id": pid, "label": str(ids["label"]),
            "faction": faction, "location": location, "demographic": "workers",
            "count": 0, "wealth": 0, "growth_rate": 0.0,
            "employed_fraction": 0.0, "migration_pressure": 0.0,
            "spending_rate": 0.02,
            "consumption": {"food": 1.0, "water": 0.6},
            "production_commodity": null, "production_amount": 0.0,
            "overall_sentiment": 50, "unrest": 0,
            "food_satisfaction": 50, "safety_satisfaction": 50,
            "entertainment_satisfaction": 50,
            "native_db_id": db_id, "construction_source_site_id": str(site_id),
            "colony_dock_id": fid}
        staged["construction_receipts"][receipt_id] = {
            "id": receipt_id, "kind": "colony_dock_prepared",
            "site_id": str(site_id), "facility_id": fid,
            "population_id": pid, "faction_id": faction,
            "destination_location": location, "body_id": body,
            "native_db_id": db_id, "tick": tick,
            "credits": 0, "population_count": 0}
        created.append({"site_id": str(site_id), "facility_id": fid,
            "population_id": pid, "destination_location": location,
            "native_db_id": db_id, "tick": tick})
    return {"ok": true, "world": staged, "created": created,
        "status": "N151_SOURCE_EMPTY_COLONY_DOCK_PREPARED" if not created.is_empty() else "N151_NO_NEW_DOCKS"}
