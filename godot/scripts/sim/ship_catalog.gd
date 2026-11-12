extends RefCounted
## Frozen Rust parity: native/crates/sim_core/src/simulation/config.rs
## ShipSize and SHIP_CLASSES; no invented classes or derived balancing.
const SIZES := ["tiny", "small", "medium", "large", "huge", "massive"]
const SIZE_SPEED := [1.15, 1.05, 1.0, 0.90, 0.80, 0.70]
const CLASSES := {
	"colonizer": {"cargo_capacity": 500, "passenger_capacity": 50, "fuel_capacity": 250.0, "fuel_consumption_base": 0.04, "speed_modifier": 1.0, "crew_roles": ["pilot", "engineer", "engineer", "medic", "general", "general"], "default_size": "medium"},
	"courier": {"cargo_capacity": 50, "passenger_capacity": 20, "fuel_capacity": 80.0, "fuel_consumption_base": 0.03, "speed_modifier": 1.5, "crew_roles": ["pilot", "general"], "default_size": "small"},
	"freighter": {"cargo_capacity": 500, "passenger_capacity": 10, "fuel_capacity": 100.0, "fuel_consumption_base": 0.05, "speed_modifier": 1.0, "crew_roles": ["pilot", "engineer", "trader", "medic", "general"], "default_size": "medium"},
	"hauler": {"cargo_capacity": 2000, "passenger_capacity": 5, "fuel_capacity": 200.0, "fuel_consumption_base": 0.10, "speed_modifier": 0.6, "crew_roles": ["pilot", "pilot", "engineer", "engineer", "trader", "medic", "general", "general"], "default_size": "huge"},
	"tanker": {"cargo_capacity": 1500, "passenger_capacity": 0, "fuel_capacity": 300.0, "fuel_consumption_base": 0.08, "speed_modifier": 0.7, "crew_roles": ["pilot", "engineer", "engineer", "trader", "medic", "general"], "default_size": "large"},
	"miner": {"cargo_capacity": 200, "passenger_capacity": 0, "fuel_capacity": 120.0, "fuel_consumption_base": 0.04, "speed_modifier": 0.8, "crew_roles": ["pilot", "engineer", "general"], "default_size": "small"},
}

static func spec(ship_class: String) -> Dictionary:
	return CLASSES.get(ship_class, {}).duplicate(true)

static func size_tier(size: String) -> int:
	var index := SIZES.find(size)
	return index + 1 if index >= 0 else 0

static func size_speed(size: String) -> float:
	var index := SIZES.find(size)
	return SIZE_SPEED[index] if index >= 0 else 0.0

static func effective_speed(ship_class: String, size: String = "") -> float:
	var entry := spec(ship_class)
	if entry.is_empty():
		return 0.0
	var tier := size if not size.is_empty() else str(entry["default_size"])
	return float(entry["speed_modifier"]) * size_speed(tier)

static func validate_catalog() -> bool:
	if CLASSES.size() != 6 or SIZES.size() != 6:
		return false
	for key in CLASSES:
		var entry: Dictionary = CLASSES[key]
		if int(entry["cargo_capacity"]) <= 0 or float(entry["fuel_capacity"]) <= 0.0:
			return false
		if (entry["crew_roles"] as Array).is_empty() or size_tier(str(entry["default_size"])) == 0:
			return false
	return true
