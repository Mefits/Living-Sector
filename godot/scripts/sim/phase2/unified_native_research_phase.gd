extends RefCounted
## P2 Gate4: N155 director observation → N143 source paid research intent.
## Read-only adapter over ONE N39 World; no treasury, stock or tech changes.
## Every source input is reconstructed from actual N39 households/markets
## and original frozen faction profile, not a new faction simulation.
const Director = preload("res://scripts/sim/phase1/n143_native_research_director.gd")
const Observer = preload("res://scripts/sim/phase1/n155_director_native_observation.gd")
const Shift = preload("res://scripts/sim/phase1/n143_native_research_shift.gd")
const Payroll = preload("res://scripts/sim/phase1/n39_native_paid_shift.gd")
const Technology = preload("res://scripts/sim/strategy/native_technology_catalog.gd")

static func _population_rows(world: Dictionary, occupied: Dictionary) -> Array:
    var output: Array = []
    var ids: Array = world["populations"].keys()
    ids.sort()
    for id in ids:
        var row: Dictionary = world["populations"][id]
        output.append({"id": str(id), "faction_id": str(row["faction"]),
            "facility_location": str(row["location"]),
            "location": str(row["location"]),
            "population_count": int(row["count"]),
            "wealth": int(row["wealth"]),
            "occupied_workers": int(occupied.get(id, 0))})
    return output

static func _market_rows(world: Dictionary) -> Array:
    var rows: Array = []
    var locations: Array = world["markets"].keys()
    locations.sort()
    for location in locations:
        var m: Dictionary = world["markets"][location]
        var facility: Dictionary = world["facilities"][str(m["owner"])]
        rows.append({"id": str(m["id"]), "facility_id": str(m["owner"]),
            "owner_faction": str(facility["faction"]),
            "facility_type": str(facility["type"]), "location": str(location),
            "electronics_supply": float(m["supply"].get("electronics", 0.0)),
            "electronics_price": float(m["prices"].get("electronics", -1.0)),
            "facility_credits": int(facility["credits"])})
    return rows

static func propose(world: Dictionary, seed_factions: Dictionary,
        tick: int, multiplier: int) -> Dictionary:
    if tick < 1 or multiplier < 1:
        return {"ok": false, "reason": "invalid_native_science_tick"}
    for field in ["faction_treasuries", "research_directors", "research_receipts"]:
        if not world.has(field):
            return {"ok": true, "status": "LEGACY_RESEARCH_COMPONENT_ABSENT",
                "heads": {}, "shifts": [], "blocked": []}
        if not (world[field] is Dictionary):
            return {"ok": false, "reason": "invalid_faction_science_domain"}
    if not (world.get("markets") is Dictionary) or not (world.get("facilities") is Dictionary) or not (world.get("populations") is Dictionary):
        return {"ok": false, "reason": "missing_real_science_economy"}
    var occupied: Dictionary = Payroll.occupied(world, tick)
    var people: Array = _population_rows(world, occupied)
    var markets: Array = _market_rows(world)
    var market_map: Dictionary = {}
    for location in world["markets"]:
        market_map[location] = world["markets"][location]
    var native_facilities: Array = []
    var facility_ids: Array = world["facilities"].keys()
    facility_ids.sort()
    for id in facility_ids:
        var f: Dictionary = world["facilities"][id]
        native_facilities.append({"id": str(id), "faction_id": str(f["faction"]),
            "facility_type": str(f["type"]), "location_name": str(f["location"])})
    var heads: Dictionary = {}
    var shifts: Array = []
    var blocked: Array = []
    var factions: Array = world["faction_treasuries"].keys()
    factions.sort()
    for fid in factions:
        var faction: String = str(fid)
        if not seed_factions.has(faction) or not world["research_directors"].has(faction):
            return {"ok": false, "reason": "unverified_original_faction"}
        var old_head: Dictionary = world["research_directors"][faction]
        var native_snapshot: Dictionary = {
            "population": people, "markets_by_location": market_map,
            "facilities": native_facilities, "contracts": []}
        var observed: Dictionary = Observer.observe_commander(
            old_head, seed_factions[faction], native_snapshot, tick, multiplier)
        if observed.is_empty():
            return {"ok": false, "reason": "n155_commander_observation_failed"}
        var selected: Dictionary = Director.observe_research(observed, {},
            {}, Technology.all())
        if not selected.get("ok", false):
            return {"ok": false, "reason": str(selected.get("reason", "n143_observe_failed"))}
        var head: Dictionary = selected["commander"]
        heads[faction] = head
        var intent: Dictionary = Shift.prepare_paid_shift({
            "faction_id": faction, "tick": tick,
            "commander": head, "markets": markets,
            "people": people, "treasury": int(world["faction_treasuries"][faction]),
            "mandate": {}, "charter": {}
        }, Technology.all())
        if intent.get("ok", false):
            shifts.append(intent)
        else:
            blocked.append({"faction_id": faction,
                "target": str(head.get("research", "")),
                "reason": str(intent.get("reason", "source_science_not_ready"))})
    return {"ok": true, "status": "SOURCE_N143_SCIENCE_OBSERVED",
        "heads": heads, "shifts": shifts, "blocked": blocked}
