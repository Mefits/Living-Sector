extends RefCounted
## N50: Rust-native aggregate ship crew for a FRESH fleet, not individual nodes.
## Sources: frozen sim_db/spawner.rs ShipCrew / ShipCrewSkills::for_roles.
## The roster never grants cargo, funds, crew wages or personnel transport.
const Catalog = preload("res://scripts/sim/ship_catalog.gd")
const TASKS = ["idle", "piloting", "engineering", "trading", "loading",
    "unloading", "eating", "resting", "on_mission"]
const INITIAL_HUNGER := 10.0
const INITIAL_MORALE := 70.0
const INITIAL_FATIGUE := 10.0
const INITIAL_HEALTH := 100.0

var crews: Dictionary = {}
var _initialized: bool = false

func initialize_new_game(fleet: RefCounted) -> bool:
    if _initialized or not _valid_fleet(fleet):
        return false
    var staged: Dictionary = {}
    for id in _sorted_ids(fleet.ships):
        var ship: Dictionary = fleet.ships[id]
        if not _fresh_ship_matches_class(ship):
            return false
        var roles: Array = (ship["crew_roles"] as Array).duplicate(true)
        staged[id] = {
            "ship_id": str(id),
            "size": int(ship["crew_size"]),
            "roles": roles,
            "hunger": INITIAL_HUNGER,
            "morale": INITIAL_MORALE,
            "fatigue": INITIAL_FATIGUE,
            "health": INITIAL_HEALTH,
            "wages_credits": 0,
            "current_task": "idle",
            "skills": _skills_for_roles(roles)
        }
    crews = staged
    _initialized = true
    return true

func snapshot() -> Array:
    var result: Array = []
    for id in _sorted_ids(crews):
        result.append((crews[id] as Dictionary).duplicate(true))
    return result

## Restore a complete existing roster, never refill morale or wages.
## Every field is checked and the swap is all-or-nothing.
func restore(records: Array, fleet: RefCounted) -> bool:
    if not _valid_fleet(fleet) or records.size() != fleet.ships.size():
        return false
    var staged: Dictionary = {}
    for value in records:
        if not (value is Dictionary):
            return false
        var record: Dictionary = value
        var id: String = str(record.get("ship_id", ""))
        if id.is_empty() or staged.has(id) or not fleet.ships.has(id):
            return false
        var ship: Dictionary = fleet.ships[id]
        var spec: Dictionary = Catalog.spec(str(ship.get("class", "")))
        if spec.is_empty():
            return false
        var roles: Variant = record.get("roles", null)
        if not (roles is Array) or roles != spec["crew_roles"]:
            return false
        if not _exact_nonnegative_int(record.get("size", null)) or int(record["size"]) != roles.size():
            return false
        if int(record["size"]) != int(ship.get("crew_size", -1)):
            return false
        for field in ["hunger", "morale", "fatigue", "health"]:
            if not _bounded_stat(record.get(field, null)):
                return false
        if not _exact_nonnegative_int(record.get("wages_credits", null)):
            return false
        if not TASKS.has(str(record.get("current_task", ""))):
            return false
        var skills: Variant = record.get("skills", null)
        if not (skills is Dictionary) or skills.size() != 4:
            return false
        for skill_name in ["navigation", "engineering", "trading", "combat"]:
            if not _exact_nonnegative_int(skills.get(skill_name, null)) or int(skills[skill_name]) > 100:
                return false
        staged[id] = record.duplicate(true)
    crews = staged
    _initialized = true
    return true

func efficiency(ship_id: String) -> float:
    if not crews.has(ship_id):
        return -1.0
    var crew: Dictionary = crews[ship_id]
    return clampf(float(crew["health"]) / 100.0 * 0.6
        + float(crew["morale"]) / 100.0 * 0.4, 0.1, 1.0)

static func _skills_for_roles(roles: Array) -> Dictionary:
    var skills: Dictionary = {
        "navigation": 30, "engineering": 30, "trading": 30, "combat": 20
    }
    for role in roles:
        var name: String = ""
        match str(role):
            "pilot":
                name = "navigation"
            "engineer":
                name = "engineering"
            "trader":
                name = "trading"
        if not name.is_empty():
            skills[name] = mini(100, int(skills[name]) + 10)
    return skills

static func _sorted_ids(value: Dictionary) -> Array:
    var ids: Array = value.keys()
    ids.sort()
    return ids

static func _valid_fleet(fleet: RefCounted) -> bool:
    return fleet != null and (fleet.get("ships") is Dictionary) and not fleet.ships.is_empty()

static func _fresh_ship_matches_class(ship: Dictionary) -> bool:
    var spec: Dictionary = Catalog.spec(str(ship.get("class", "")))
    if spec.is_empty():
        return false
    if str(ship.get("id", "")).is_empty():
        return false
    var roles: Variant = ship.get("crew_roles", null)
    if not (roles is Array) or roles != spec["crew_roles"]:
        return false
    if int(ship.get("crew_size", -1)) != roles.size() or roles.is_empty():
        return false
    if not (ship.get("cargo", null) is Dictionary) or not ship["cargo"].is_empty():
        return false
    if not (ship.get("transit", null) is Dictionary) or not ship["transit"].is_empty():
        return false
    var capacity: float = float(spec["fuel_capacity"])
    var remaining: float = float(ship.get("fuel", -1.0))
    return is_finite(remaining) and is_equal_approx(remaining, capacity)

static func _bounded_stat(value: Variant) -> bool:
    return (value is int or value is float) and is_finite(float(value))         and float(value) >= 0.0 and float(value) <= 100.0

static func _exact_nonnegative_int(value: Variant) -> bool:
    return typeof(value) == TYPE_INT and int(value) >= 0
