extends RefCounted
## N40/N46: seed identity check. Native 0.6.7 ships have NO persistent IDs,
## cargo or fuel entries. N46 may derive full tanks and empty holds ONLY for
## fresh games by the frozen Rust sim_db::seeder source, not from save/restore.
## Source: N4 world_registry.gd (system + array ordinal).
const Registry = preload("res://scripts/sim/world_registry.gd")
const Catalog = preload("res://scripts/sim/ship_catalog.gd")
var registry: RefCounted
var _roster: Dictionary = {}

func load_seed(seed: Dictionary) -> bool:
    var staged_registry = Registry.new()
    if not staged_registry.load_seed(seed):
        return false
    var staged: Dictionary = {}
    for ship_key in staged_registry.keys_for("ship"):
        var record: Dictionary = staged_registry.get_entity("ship", str(ship_key))
        var source: Dictionary = record.get("value", {})
        var ship_class: String = str(source.get("class", ""))
        var location: String = str(source.get("location", ""))
        var faction: String = str(source.get("faction_id", ""))
        var system_id: String = str(record.get("system_id", ""))
        if Catalog.spec(ship_class).is_empty() or location.is_empty() or faction.is_empty() or system_id.is_empty():
            return false
        if not staged_registry.graph().has_location(location):
            return false
        staged[str(ship_key)] = {
            "class": ship_class,
            "location": location,
            "faction_id": faction,
            "system_id": system_id,
            "name": str(source.get("name", ""))
        }
    registry = staged_registry
    _roster = staged
    return not _roster.is_empty()

func keys() -> PackedStringArray:
    var result := PackedStringArray()
    for id in _roster:
        result.append(str(id))
    result.sort()
    return result

func metadata(ship_id: String) -> Dictionary:
    return (_roster.get(ship_id, {}) as Dictionary).duplicate(true)

## Caller must provide provenance for fuel/cargo on EVERY registered ship.
## For clean first-run native seeds, N46 sources values from Rust seeder;
## saved games must restore their exact balances and NEVER use N46 defaults.
func validate_authoritative_state(state: RefCounted, fuel_sources: Dictionary, cargo_sources: Dictionary) -> bool:
    if registry == null or state == null or not (state.get("ships") is Dictionary) or not state.has_method("can_hold") or not state.has_method("snapshot"):
        return false
    if state.ships.is_empty() or state.ships.size() > _roster.size():
        return false
    if fuel_sources.size() != state.ships.size() or cargo_sources.size() != state.ships.size():
        return false
    for id in state.ships:
        var ship_id: String = str(id)
        if not _roster.has(ship_id) or not fuel_sources.has(ship_id) or not cargo_sources.has(ship_id):
            return false
        var expected: Dictionary = _roster[ship_id]
        var value: Variant = state.ships[id]
        if not (value is Dictionary):
            return false
        var ship: Dictionary = value
        if str(ship.get("id", "")) != ship_id or str(ship.get("class", "")) != str(expected["class"]):
            return false
        if str(ship.get("faction_id", "")) != str(expected["faction_id"]) or str(ship.get("system_id", "")) != str(expected["system_id"]):
            return false
        if str(ship.get("location", "")) != str(expected["location"]) or not (ship.get("transit", null) is Dictionary) or not ship["transit"].is_empty():
            return false
        var fuel: Variant = fuel_sources[ship_id]
        var cargo: Variant = cargo_sources[ship_id]
        if not (fuel is float or fuel is int) or not is_finite(float(fuel)):
            return false
        if not (cargo is Dictionary) or ship.get("cargo", null) != cargo:
            return false
        if float(fuel) < 0.0 or float(fuel) > float(ship.get("fuel_capacity", -1.0)) or not is_equal_approx(float(ship.get("fuel", -1.0)), float(fuel)):
            return false
        var spec: Dictionary = Catalog.spec(str(expected["class"]))
        if int(ship.get("cargo_capacity", -1)) != int(spec["cargo_capacity"]) or not is_equal_approx(float(ship.get("fuel_capacity", -1.0)), float(spec["fuel_capacity"])):
            return false
        if not state.can_hold(ship_id, cargo):
            return false
    return true
