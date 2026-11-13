extends RefCounted
## N46: reproduce *fresh* ship initialization of frozen Rust seeder.rs.
## Native ship JSON omits fuel/cargo; Rust seeder creates a new DB row with
## fuel=fuel_capacity and cargo='{}', NOT a resume/restore of a live fleet.
## This bootstrap is strictly clean-game-only. No money is minted here.
const Catalog = preload("res://scripts/sim/ship_catalog.gd")
const ShipState = preload("res://scripts/sim/ship_state.gd")
const Roster = preload("res://scripts/sim/ships/native_ship_roster.gd")
const PROVENANCE: String = "frozen-rust-sim_db-seeder-fresh-ship-20261112"

static func build_new_game(seed: Dictionary) -> Dictionary:
    var roster = Roster.new()
    if not roster.load_seed(seed):
        return _reject("invalid_native_seed_roster")
    var fleet = ShipState.new()
    var fuel: Dictionary = {}
    var cargo: Dictionary = {}
    var credits: Dictionary = {}
    var keys: PackedStringArray = roster.keys()
    if keys.is_empty():
        return _reject("empty_native_fleet")
    for ship_id in keys:
        var lookup: Dictionary = roster.registry.get_entity("ship", str(ship_id))
        var value: Variant = lookup.get("value", null)
        if not (value is Dictionary):
            return _reject("invalid_ship_record")
        var source: Dictionary = value
        # An arbitrary user-save or evolving runtime ship state must NEVER
        # be mistaken for Rust's new-game seed, or be refilled silently.
        for prohibited_key in ["id", "fuel", "fuel_capacity", "cargo", "transit", "cargo_age",
                "cargo_origin", "active_contract_id", "resume_json"]:
            if source.has(prohibited_key):
                return _reject("not_a_clean_new_game_seed")
        var ship_class: String = str(source.get("class", ""))
        var meta: Dictionary = roster.metadata(str(ship_id))
        var spec: Dictionary = Catalog.spec(ship_class)
        if spec.is_empty():
            return _reject("unknown_ship_class")
        var size: String = str(source.get("size", spec["default_size"]))
        if Catalog.size_tier(size) == 0:
            return _reject("unknown_ship_size")
        var raw_fitting: Variant = source.get("fitting", {})
        if not (raw_fitting is Dictionary):
            return _reject("invalid_seed_fitting")
        var fitting: Dictionary = raw_fitting
        # The bundled frozen 24-ship seed contains only comms_t2 overrides.
        # Other fittings may change cargo/speed, which this ShipState model
        # cannot yet apply faithfully. Refuse rather than mis-simulate.
        for slot_name in fitting:
            if str(slot_name) != "comms" or str(fitting[slot_name]) != "comms_t2":
                return _reject("unimplemented_fitting_modifier")
        var raw_credits: Variant = source.get("credits", null)
        if not _nonnegative_whole(raw_credits):
            return _reject("invalid_seed_credits")
        if not fleet.add_ship(str(ship_id), ship_class, str(meta["faction_id"]),
                str(meta["system_id"]), size):
            return _reject("ship_creation_failed")
        var state: Dictionary = fleet.ships[ship_id]
        state["location"] = str(meta["location"])
        # Rust native/crates/sim_db/src/seeder.rs INSERT INTO ships:
        # cargo defaults to empty and initial fuel to the exact class cap.
        # No N15 transfer, refuel operation or inventory supply is generated.
        fuel[ship_id] = float(spec["fuel_capacity"])
        cargo[ship_id] = {}
        # This is SOURCE DATA, not a second credit ledger; no balance is
        # mutated or credited until a real economy world adapter exists.
        credits[ship_id] = int(raw_credits)
    if fleet.ships.size() != keys.size() or not roster.validate_authoritative_state(
            fleet, fuel, cargo):
        return _reject("fleet_provenance_mismatch")
    return {
        "ok": true,
        "provenance": PROVENANCE,
        "ship_count": keys.size(),
        "fleet": fleet,
        "fuel_sources": fuel,
        "cargo_sources": cargo,
        "credit_sources": credits
    }

static func _nonnegative_whole(value: Variant) -> bool:
    if not (value is int or value is float) or not is_finite(float(value)):
        return false
    return float(value) >= 0.0 and float(value) <= 9007199254740991.0 and float(int(value)) == float(value)

static func _reject(reason: String) -> Dictionary:
    return {"ok": false, "error": reason}
