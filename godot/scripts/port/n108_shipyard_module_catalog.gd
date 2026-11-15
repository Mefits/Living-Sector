extends RefCounted
## N108: exact static module definitions from frozen
## sim_core/modules/mod.rs and recipe prices from
## sim_core/economy/module_production.rs; ship base stats from
## sim_core/simulation/config.rs. N51 initial fitting already mirrors
## these definitions; Phase 2 must unify to ONE catalog (no double source).
const SLOTS = ["engine", "cargo_bay", "sensors", "reactor", "comms"]
const CLASSES = {
    "colonizer": {"base_cargo": 500, "base_speed": 1.0},
    "courier": {"base_cargo": 50, "base_speed": 1.5},
    "freighter": {"base_cargo": 500, "base_speed": 1.0},
    "hauler": {"base_cargo": 2000, "base_speed": 0.6},
    "tanker": {"base_cargo": 1500, "base_speed": 0.7},
    "miner": {"base_cargo": 200, "base_speed": 0.8}
}
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
## Strictly shipyard-produced t2/t3 modules. Tier 1 defaults are
## free on spawn, NOT purchasable as a manufactured ModuleRecipe.
const PRICE_BY_SLUG = {
    "engine_t2": 8000, "engine_t3": 22000,
    "cargo_bay_t2": 6000, "cargo_bay_t3": 16000,
    "sensors_t2": 7500, "sensors_t3": 20000,
    "reactor_t2": 10000, "reactor_t3": 28000,
    "comms_t2": 5500, "comms_t3": 14000
}

static func combine(slots: Dictionary) -> Dictionary:
    if slots.size() != SLOTS.size():
        return {}
    var derived: Dictionary = {
        "speed_mult": 1.0, "cargo_capacity_mult": 1.0,
        "fuel_efficiency_mult": 1.0, "sensor_range_au": 0.0,
        "comms_bonus": 0.0, "power_use": 0, "power_cap": 0
    }
    for key in SLOTS:
        if not slots.has(key):
            return {}
        var slug: Variant = slots[key]
        if slug == null:
            continue
        if not (slug is String) or not MODULES.has(slug):
            return {}
        var module: Dictionary = MODULES[slug]
        if str(module.get("slot", "")) != key:
            return {}
        # Frozen Rust combines multiplicative effects, additive range
        # and comms; power use and provided saturate to u16.
        derived["speed_mult"] *= float(module.get("speed", 1.0))
        derived["cargo_capacity_mult"] *= float(module.get("cargo", 1.0))
        derived["fuel_efficiency_mult"] *= float(module.get("fuel", 1.0))
        derived["sensor_range_au"] += float(module.get("range", 0.0))
        derived["comms_bonus"] += float(module.get("bonus", 0.0))
        derived["power_use"] = mini(65535,
            int(derived["power_use"]) + int(module.get("draw", 0)))
        derived["power_cap"] = mini(65535,
            int(derived["power_cap"]) + int(module.get("provide", 0)))
    # Rust exposes power_ok but does NOT enforce it at refit-Apply.
    derived["power_ok"] = int(derived["power_use"]) <= int(derived["power_cap"])
    return derived

static func slot_and_recipe(slug: String, slot: String) -> Dictionary:
    if not SLOTS.has(slot) or not MODULES.has(slug):
        return {"ok": false, "reason": "invalid_slug"}
    if str(MODULES[slug].get("slot", "")) != slot:
        return {"ok": false, "reason": "wrong_slot"}
    if not PRICE_BY_SLUG.has(slug):
        return {"ok": false, "reason": "unmanufactured_module"}
    return {"ok": true, "cost": int(PRICE_BY_SLUG[slug])}
