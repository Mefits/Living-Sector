extends RefCounted
## N150 frozen agents/faction_relations.rs + celestial_body.rs integration.
## SOURCE projections only; the existing N39 World is the sole writer.
## Never grant credits, new factions, treaties, buildings or territory here.
const Relations = preload("res://scripts/sim/phase1/n150_native_full_faction_relations.gd")
const Territory = preload("res://scripts/sim/phase1/n150_native_market_territory.gd")

## Called only from the real "relations" phase after factions/colonies.
static func propose_pass(state: Dictionary, tick: int, multiplier: int) -> Dictionary:
    if tick < 1 or multiplier < 1 or not (state.get("faction_relations", {}) is Dictionary):
        return {"ok": false, "reason": "n150_missing_faction_relations_authority"}
    var pairs: Dictionary = state.get("faction_relations", {})
    if not Relations.validate_pairs(pairs):
        return {"ok": false, "reason": "n150_invalid_native_treaty_pairs"}
    if not Relations.pass_due(tick, multiplier):
        return {"ok": true, "due": false, "tick": tick, "pairs": pairs.duplicate(true),
            "treaty_changes": []}
    var result: Dictionary = Relations.tick_relations(pairs, tick, multiplier)
    if not result.get("ok", false):
        return result
    return {"ok": true, "due": true, "tick": tick,
        "pairs": result["pairs"].duplicate(true),
        "treaty_changes": result.get("treaty_changes", []).duplicate(true)}

## Pure original source BodyTerritory + SystemControl projection from the
## LIVE Godot orbital registry and N39 physical facility accounts.
## ConstructionSites are NOT finished facilities, so cannot vote.
static func territory(state: Dictionary, orbits: RefCounted) -> Dictionary:
    if orbits == null or not (state.get("bodies") is Dictionary) or not (state.get("facilities") is Dictionary):
        return {"ok": false, "reason": "n150_missing_real_territory_sources"}
    var bodies: Array = []
    var body_ids: Array = state["bodies"].keys()
    body_ids.sort()
    for id in body_ids:
        var native: Dictionary = orbits.body_by_id(str(id))
        var system_id: String = str(native.get("system_id", ""))
        if system_id.is_empty():
            return {"ok": false, "reason": "n150_unregistered_source_body:" + str(id)}
        bodies.append({"body_id": str(id), "system_name": system_id})
    var facilities: Array = []
    var trade_facilities: Array = []
    var facility_ids: Array = state["facilities"].keys()
    facility_ids.sort()
    for id in facility_ids:
        var f: Dictionary = state["facilities"][id]
        if not state["bodies"].has(str(f.get("body_id", ""))):
            return {"ok": false, "reason": "n150_unregistered_owner_body"}
        var faction: String = str(f.get("faction", ""))
        var location: String = str(f.get("location", ""))
        if faction.is_empty() or location.is_empty():
            return {"ok": false, "reason": "n150_invalid_physical_facility_owner"}
        facilities.append({
            "body_id": str(f["body_id"]), "faction_id": faction,
            "facility_type": str(f.get("type", "")),
            "credits": int(f.get("credits", 0))})
        trade_facilities.append({"faction_id": faction, "location": location})
    var derived: Dictionary = Territory.derive(bodies, facilities)
    if not derived.get("ok", false):
        return derived
    return {"ok": true, "tick_source": "one_n39_world_live_facilities",
        "bodies": derived["bodies"].duplicate(true),
        "systems": derived["systems"].duplicate(true),
        "market_controllers": Relations.market_controllers(trade_facilities),
        "ambiguous_rust_ties": derived.get("original_rust_undefined_equal_credit_ties", []).duplicate(true)}

## Faction relations commerce controls are enforced only at the real N97
## source purchase. No synthetic permit is needed for same-faction trade.
static func commerce_allowed(state: Dictionary, ship_id: String, location: String) -> bool:
    var ship: Dictionary = state.get("ships", {}).get(ship_id, {})
    if ship.is_empty() or location.is_empty() or not state.get("markets", {}).has(location):
        return false
    var facilities: Array = []
    var ids: Array = state.get("facilities", {}).keys()
    ids.sort()
    for id in ids:
        var f: Dictionary = state["facilities"][id]
        facilities.append({"faction_id": str(f.get("faction", "")),
            "location": str(f.get("location", ""))})
    var controllers: Dictionary = Relations.market_controllers(facilities)
    var owner: String = str(controllers.get(location, ""))
    if owner.is_empty():
        return false
    return Relations.commerce_allowed(state.get("faction_relations", {}),
        str(ship.get("faction_id", "")), owner)
