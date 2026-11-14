extends RefCounted
## N46: reproduce *fresh* ship initialization of frozen Rust seeder.rs.
## Native ship JSON omits fuel/cargo; Rust seeder creates a new DB row with
## fuel=fuel_capacity and cargo='{}', NOT a resume/restore of a live fleet.
## This bootstrap is strictly clean-game-only. No money is minted here.
const Catalog = preload("res://scripts/sim/ship_catalog.gd")
const ShipState = preload("res://scripts/sim/ship_state.gd")
const Roster = preload("res://scripts/sim/ships/native_ship_roster.gd")
const NativeInitialFitting = preload("res://scripts/sim/ships/native_initial_fitting.gd")
const ModuleCatalog = preload("res://scripts/port/n108_shipyard_module_catalog.gd")
const ShipProgression = preload("res://scripts/sim/native/ship_progression_n101.gd")
const ShipLifecycle = preload("res://scripts/sim/phase1/n148_native_ship_lifecycle.gd")
const SourceLod = preload("res://scripts/sim/phase1/n140_native_spatial_lod.gd")
const NativeCrewRoster = preload("res://scripts/sim/ships/native_crew_roster.gd")
const NativePriceMemory = preload("res://scripts/sim/phase2/unified_native_ship_price_observation.gd")
const NativeTradeSlot = preload("res://scripts/simulation/ai/native_ship_transaction_slot.gd")
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
    # Native Rust spawner N51: persist the ACTUAL initial fitting on
    # each ship, including deterministic size-based T2 sensor assignment.
    # No extra goods, retrofit points, fuel, money or random rolls.
    var projected: Dictionary = NativeInitialFitting.project_native_seed(seed, fleet)
    if not projected.get("ok", false):
        return _reject("source_N51_fitting_unavailable:" +
            str(projected.get("error", "unknown")))
    for ship_id in keys:
        var ship: Dictionary = fleet.ships[ship_id]
        var slots: Dictionary = projected["records"][ship_id]["slots"]
        var derived: Dictionary = ModuleCatalog.combine(slots)
        if derived.is_empty():
            return _reject("native_ship_fitting_catalogue_mismatch")
        var ship_spec: Dictionary = Catalog.spec(str(ship["class"]))
        ship["fitting"] = {"slots": slots.duplicate(true),
            "derived": derived.duplicate(true)}
        ship["progression"] = ShipProgression.initial_state()
        # Rust ShipLifecycle::default on fresh ECS ships; NOT a balance tweak.
        ship["lifecycle"] = ShipLifecycle.default_lifecycle()
        # Original AgentLod::new cursor on every fresh Rust ECS ship.
        # Separate from N148 strikes; no permanent source LOD service.
        ship["lod"] = SourceLod.new_cursor()
        # Rust ShipMemory::default is an empty LEARNED record, not
        # omniscient market prices from the source seed.
        ship["memory"] = NativePriceMemory.default_memory()
        # Rust ShipEconomy::default: N90 outstanding transaction is
        # empty, trade cargo has no invented origin/cost and reputation
        # is unknown until real diplomacy effects occur.
        ship["transaction"] = NativeTradeSlot.empty()
        ship["cargo_origin"] = {}
        ship["faction_reputation"] = {}
        ship["cargo_capacity"] = roundi(float(ship_spec["cargo_capacity"]) *
            float(derived["cargo_capacity_mult"]))
        ship["speed_modifier"] = Catalog.effective_speed(
            str(ship["class"]), str(ship["size"])) * float(derived["speed_mult"])
        # Rust's fuel_consumption_rate is class-base, not multiplied
        # by the fitted efficiency metadata in the native flight loop.
        ship["fuel_efficiency_mult"] = float(derived["fuel_efficiency_mult"])
        ship["comms_bonus"] = float(derived["comms_bonus"])
    # Source N50 spawner initializes the ONE aggregate ShipCrew for
    # each original N46 ship (no phantom individual crew actors).
    # Salary starts at zero, not paid at seeding; cargo ages are empty.
    var actual_crew := NativeCrewRoster.new()
    if not actual_crew.initialize_new_game(fleet):
        return _reject("native_crew_initialization_rejected")
    for record in actual_crew.snapshot():
        var crew_id: String = str(record["ship_id"])
        if not fleet.ships.has(crew_id):
            return _reject("native_crew_orphaned_from_original_ship")
        var crew: Dictionary = record.duplicate(true)
        var roles: Array = crew["roles"].duplicate(true)
        crew.erase("ship_id")
        crew.erase("roles")
        var skills: Dictionary = crew["skills"].duplicate(true)
        crew.erase("skills")
        crew["dirty"] = false
        fleet.ships[crew_id]["crew"] = crew
        fleet.ships[crew_id]["crew_skills"] = skills
        fleet.ships[crew_id]["cargo_age"] = {}
        fleet.ships[crew_id]["crew_efficiency"] = actual_crew.efficiency(crew_id)
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
