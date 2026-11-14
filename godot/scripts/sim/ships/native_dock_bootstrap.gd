extends RefCounted
## N53: native facilities and ships admitted to the N21 docking authority.
## A ship at "earth-station" is NOT automatically docked: frozen Rust
## ships INSERT leaves docked_at NULL (001_initial.sql, sim_db/seeder.rs).
## Docking itself requires explicit RequestDock / apply-phase authority.
const Roster = preload("res://scripts/sim/ships/native_ship_roster.gd")
const Docking = preload("res://scripts/sim/ships/docking_registry.gd")

static func build_new_game(seed: Dictionary, fleet: RefCounted) -> Dictionary:
    if fleet == null or not (fleet.get("ships") is Dictionary):
        return _fail("missing_fleet")
    var roster = Roster.new()
    if not roster.load_seed(seed):
        return _fail("invalid_seed")
    var ship_ids: PackedStringArray = roster.keys()
    var facility_ids: PackedStringArray = roster.registry.keys_for("facility")
    if ship_ids.size() == 0 or facility_ids.size() == 0 or fleet.ships.size() != ship_ids.size():
        return _fail("incomplete_native_state")
    var authority = Docking.new()
    var total_slots: int = 0
    for facility_id in facility_ids:
        var entry: Dictionary = roster.registry.get_entity("facility", facility_id)
        var value: Variant = entry.get("value", null)
        if not (value is Dictionary):
            return _fail("bad_facility")
        var f: Dictionary = value
        var capacity: Variant = f.get("docking_capacity", null)
        # Frozen JSON numbers may deserialize as floats. Never round a
        # fractional, nonfinite, negative or unsafe-size dock capacity.
        if not (capacity is int or capacity is float) or not is_finite(float(capacity)):
            return _fail("bad_docking_capacity")
        if float(capacity) < 0.0 or float(capacity) > 9007199254740991.0 or float(int(capacity)) != float(capacity):
            return _fail("bad_docking_capacity")
        var location: String = str(f.get("location", ""))
        var kind: String = str(f.get("type", ""))
        if location.is_empty() or kind.is_empty() or not roster.registry.graph().has_location(location):
            return _fail("facility_location_not_mapped")
        if total_slots > 9223372036854775807 - int(capacity):
            return _fail("capacity_overflow")
        if not authority.register_facility(str(facility_id), location, int(capacity), kind):
            return _fail("facility_registration_rejected")
        total_slots += int(capacity)
    for ship_id in ship_ids:
        var record: Dictionary = roster.registry.get_entity("ship", str(ship_id))
        var source: Dictionary = record.get("value", {})
        var source_location: String = str(source.get("location", ""))
        # Rust DB seeder INSERT does not specify docked_at, transit or cargo.
        # If any appear, this is a saved runtime state, not an initial seed.
        if source.has("docked_at") or source.has("transit") or source.has("transit_to"):
            return _fail("saved_ship_state_requires_restore")
        if not fleet.ships.has(ship_id):
            return _fail("missing_source_ship")
        var ship: Dictionary = fleet.ships[ship_id]
        if str(ship.get("location", "")) != source_location or str(ship.get("id", "")) != str(ship_id):
            return _fail("ship_location_identity_mismatch")
        if not (ship.get("transit", null) is Dictionary) or not (ship["transit"] as Dictionary).is_empty():
            return _fail("in_flight_ship_not_fresh")
        # Do not create a phantom dock in the registry. They are only
        # parked at a named navigation location until RequestDock succeeds.
        if not authority.register_ship(str(ship_id), source_location, false):
            return _fail("ship_registration_rejected")
    var state: Dictionary = authority.snapshot()
    for facility_id in facility_ids:
        if not (state["occupants"][facility_id] as Array).is_empty():
            return _fail("phantom_initial_occupation")
    return {"ok": true, "registry": authority, "ships": ship_ids.size(),
        "facilities": facility_ids.size(), "total_slots": total_slots}

static func _fail(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
