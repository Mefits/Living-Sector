extends RefCounted
## N65: source-parity fuel diagnostics, never an invented rescue system.
## Frozen Rust sim_core::agents::ship::mod.rs advance_transits moves even
## when current fuel is 0; it clamps the per-tick charge to 0 afterward.
const Catalog = preload("res://scripts/sim/ship_catalog.gd")

static func inspect(ship: Dictionary) -> Dictionary:
    var ship_id: String = str(ship.get("id", ""))
    var ship_class: String = str(ship.get("class", ""))
    var spec: Dictionary = Catalog.spec(ship_class)
    if ship_id.is_empty() or spec.is_empty():
        return {"ok": false, "reason": "unknown_ship_or_class"}
    var fuel: Variant = ship.get("fuel", null)
    var cap: Variant = ship.get("fuel_capacity", null)
    var transit: Variant = ship.get("transit", null)
    if not (fuel is int or fuel is float) or not (cap is int or cap is float) or not (transit is Dictionary):
        return {"ok": false, "reason": "invalid_fuel_data"}
    var f: float = float(fuel)
    var capacity: float = float(cap)
    if not is_finite(f) or not is_finite(capacity) or f < 0.0 or capacity <= 0.0 or f > capacity:
        return {"ok": false, "reason": "invalid_fuel_range"}
    var rate: float = float(spec.get("fuel_consumption_base", -1.0))
    if not is_finite(rate) or rate <= 0.0:
        return {"ok": false, "reason": "invalid_class_consumption"}
    var flying: bool = not (transit as Dictionary).is_empty()
    var state: String = "normal"
    if is_zero_approx(f):
        state = "depleted_in_transit_but_moving" if flying else "depleted_at_location"
    elif f < rate:
        state = "below_single_native_tick_base_consumption"
    return {
        "ok": true, "ship_id": ship_id,
        "fuel": f, "capacity": capacity, "fraction": f/capacity,
        "base_consumption": rate, "in_transit": flying,
        "state": state, "movement_disabled_by_empty_fuel": false
    }

static func snapshot(fleet: RefCounted) -> Dictionary:
    if fleet == null or not (fleet.get("ships") is Dictionary):
        return {"ok": false, "reason": "missing_fleet"}
    var keys: Array = fleet.ships.keys()
    keys.sort()
    var entries: Array = []
    for key in keys:
        var ship: Variant = fleet.ships[key]
        if not (ship is Dictionary):
            return {"ok": false, "reason": "bad_ship"}
        var status: Dictionary = inspect(ship)
        if not bool(status.get("ok", false)):
            return status
        entries.append(status)
    return {"ok": true, "ships": entries}
