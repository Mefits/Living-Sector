extends RefCounted
## N51: read-only exact *initial* Rust ShipFitting projection (Phase 18f).
## Ship source ID is Rust spawner: ship-{lowercase-name with spaces->dashes}.
## No refit or inventory mutation, and no random roll on load.
const Roster = preload("res://scripts/sim/ships/native_ship_roster.gd")
const Catalog = preload("res://scripts/sim/ship_catalog.gd")
const SLOTS = ["engine", "cargo_bay", "sensors", "reactor", "comms"]
const DEFAULTS = {
    "engine": "engine_t1", "cargo_bay": "cargo_bay_t1",
    "sensors": "sensors_t1", "reactor": "reactor_t1", "comms": "comms_t1"
}
## Exact native/crates/sim_core/src/modules/mod.rs CATALOG.
const MODULES = {
    "engine_t1": {"slot": "engine", "speed": 1.0, "fuel": 1.0, "draw": 2},
    "engine_t2": {"slot": "engine", "speed": 1.15, "fuel": 0.95, "draw": 4},
    "engine_t3": {"slot": "engine", "speed": 1.30, "fuel": 0.90, "draw": 6},
    "cargo_bay_t1": {"slot": "cargo_bay", "cargo": 1.0, "draw": 0},
    "cargo_bay_t2": {"slot": "cargo_bay", "cargo": 1.20, "draw": 1},
    "cargo_bay_t3": {"slot": "cargo_bay", "cargo": 1.40, "draw": 2},
    "sensors_t1": {"slot": "sensors", "range": 1.0, "draw": 1},
    "sensors_t2": {"slot": "sensors", "range": 2.0, "draw": 2},
    "sensors_t3": {"slot": "sensors", "range": 3.5, "draw": 4},
    "reactor_t1": {"slot": "reactor", "provide": 10},
    "reactor_t2": {"slot": "reactor", "provide": 15},
    "reactor_t3": {"slot": "reactor", "provide": 22},
    "comms_t1": {"slot": "comms", "bonus": 0.0, "draw": 1},
    "comms_t2": {"slot": "comms", "bonus": 0.05, "draw": 2},
    "comms_t3": {"slot": "comms", "bonus": 0.10, "draw": 3}
}

static func project_native_seed(seed: Dictionary, fleet: RefCounted) -> Dictionary:
    if fleet == null or not (fleet.get("ships") is Dictionary):
        return _reject("missing_fleet")
    var roster = Roster.new()
    if not roster.load_seed(seed) or roster.keys().size() != fleet.ships.size():
        return _reject("invalid_roster_or_incomplete_fleet")
    var records: Dictionary = {}
    var native_ids: Dictionary = {}
    for id in roster.keys():
        if not fleet.ships.has(id):
            return _reject("unknown_fleet_ship")
        var entry: Dictionary = roster.registry.get_entity("ship", str(id))
        var source: Dictionary = entry.get("value", {})
        var ship: Dictionary = fleet.ships[id]
        var ship_class: String = str(source.get("class", ""))
        var spec: Dictionary = Catalog.spec(ship_class)
        if spec.is_empty() or str(ship.get("class", "")) != ship_class:
            return _reject("invalid_class")
        var size: String = str(ship.get("size", ""))
        if Catalog.size_tier(size) == 0:
            return _reject("invalid_size")
        var expected_size: String = str(source.get("size", spec["default_size"]))
        if expected_size != size:
            return _reject("fleet_size_mismatch")
        var rust_id: String = rust_ship_id_from_seed_name(str(source.get("name", "")))
        if rust_id.is_empty() or native_ids.has(rust_id):
            return _reject("rust_persistent_id_unavailable_or_duplicate")
        native_ids[rust_id] = true
        var slots: Dictionary = DEFAULTS.duplicate(true)
        var tier: int = Catalog.size_tier(size)
        if tier >= 5 or (tier == 4 and _large_ship_tier2_sensors(rust_id)):
            slots["sensors"] = "sensors_t2"
        var fitting_source: Variant = source.get("fitting", {})
        if not (fitting_source is Dictionary):
            return _reject("invalid_seed_fitting")
        for raw_slot in fitting_source:
            var slot_name: String = str(raw_slot)
            if not SLOTS.has(slot_name):
                return _reject("unknown_fitting_slot")
            var slug: Variant = fitting_source[raw_slot]
            if not (slug is String) or not MODULES.has(slug) or str(MODULES[slug]["slot"]) != slot_name:
                return _reject("unknown_or_mismatched_module")
            slots[slot_name] = slug
        var effects: Dictionary = _combine(slots)
        if effects.is_empty():
            return _reject("invalid_fitting_effects")
        if int(ship.get("cargo_capacity", -1)) != roundi(float(spec["cargo_capacity"]) * float(effects["cargo_mult"])):
            return _reject("nonapplied_cargo_fitting")
        # N46 / N13 supports only the vanilla speed: any fitted speed
        # modifier requires a separate ship-propulsion integration first.
        if not is_equal_approx(float(effects["speed_mult"]), 1.0) or not is_equal_approx(float(effects["fuel_mult"]), 1.0):
            return _reject("nonapplied_propulsion_fitting")
        records[id] = {
            "ship_id": str(id), "rust_ship_id": rust_id,
            "slots": slots, "effects": effects,
            "native_effective_speed": Catalog.effective_speed(ship_class, size),
            "native_cargo_capacity": int(ship["cargo_capacity"])
        }
    return {"ok": true, "records": records, "ship_count": records.size()}

## Frozen Rust spawner.rs: format!("ship-{}", name.to_lowercase()
##     .replace(' ', "-").replace(|c: char| !c.is_alphanumeric() && c != '-', "")).
## Native 24-ship seed is ASCII. Refuse non-ASCII without a source-parity
## Unicode alphanumeric implementation rather than silently changing IDs.
static func rust_ship_id_from_seed_name(name: String) -> String:
    if name.is_empty():
        return ""
    var raw: String = name.to_lower().replace(" ", "-")
    var cleaned: String = ""
    for i in range(raw.length()):
        var code: int = raw.unicode_at(i)
        if code > 127:
            return ""
        if (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 45:
            cleaned += raw.substr(i, 1)
    return "ship-" + cleaned if not cleaned.is_empty() else ""

## Only parity matters: FNV-1a multiplier is odd, so each iteration's low
## bit is previous_low_bit XOR (byte & 1). Exact Rust u64-even result.
static func _large_ship_tier2_sensors(rust_id: String) -> bool:
    var parity: int = 1 # Rust FNV-1a offset 0xcbf29ce484222325 low bit.
    for byte_value in rust_id.to_utf8_buffer():
        parity = parity ^ (int(byte_value) & 1)
    return parity == 0

static func _combine(slots: Dictionary) -> Dictionary:
    if slots.size() != SLOTS.size():
        return {}
    var result: Dictionary = {
        "speed_mult": 1.0, "cargo_mult": 1.0, "fuel_mult": 1.0,
        "sensor_range_au": 0.0, "comms_bonus": 0.0,
        "power_use": 0, "power_cap": 0
    }
    for slot in SLOTS:
        var slug: String = str(slots.get(slot, ""))
        if not MODULES.has(slug):
            return {}
        var module: Dictionary = MODULES[slug]
        if str(module["slot"]) != slot:
            return {}
        result["speed_mult"] *= float(module.get("speed", 1.0))
        result["cargo_mult"] *= float(module.get("cargo", 1.0))
        result["fuel_mult"] *= float(module.get("fuel", 1.0))
        result["sensor_range_au"] += float(module.get("range", 0.0))
        result["comms_bonus"] += float(module.get("bonus", 0.0))
        result["power_use"] += int(module.get("draw", 0))
        result["power_cap"] += int(module.get("provide", 0))
    result["power_ok"] = int(result["power_use"]) <= int(result["power_cap"])
    return result

static func _reject(error: String) -> Dictionary:
    return {"ok": false, "error": error}
