extends RefCounted
## Data-only ship state; Rust components: ShipIdentity, ShipCargo, ShipFuel,
## ShipCrew and ShipPosition. Economic transfers are NOT performed here.
const Catalog = preload("res://scripts/sim/ship_catalog.gd")
const ModuleCatalog = preload("res://scripts/port/n108_shipyard_module_catalog.gd")
const Progression = preload("res://scripts/sim/native/ship_progression_n101.gd")
var ships: Dictionary = {}

func add_ship(id: String, ship_class: String, faction_id: String, system_id: String, size: String = "") -> bool:
	if id.is_empty() or faction_id.is_empty() or system_id.is_empty() or ships.has(id):
		return false
	var spec := Catalog.spec(ship_class)
	if spec.is_empty():
		return false
	var resolved_size := size if not size.is_empty() else str(spec["default_size"])
	if Catalog.size_tier(resolved_size) == 0:
		return false
	ships[id] = {
		"id": id, "class": ship_class, "faction_id": faction_id,
		"system_id": system_id, "size": resolved_size,
		"cargo_capacity": int(spec["cargo_capacity"]), "cargo": {},
		"fuel": float(spec["fuel_capacity"]), "fuel_capacity": float(spec["fuel_capacity"]),
		"crew_size": (spec["crew_roles"] as Array).size(),
		"crew_roles": (spec["crew_roles"] as Array).duplicate(),
		"location": "", "transit": {},
	}
	return true

func cargo_used(id: String) -> int:
	if not ships.has(id):
		return -1
	var total := 0
	for amount in (ships[id]["cargo"] as Dictionary).values():
		total += int(amount)
	return total

func cargo_free(id: String) -> int:
	if not ships.has(id):
		return -1
	return maxi(0, int(ships[id]["cargo_capacity"]) - cargo_used(id))

## Validates prospective state only. N15 owns actual cargo transfer and receipts.
func can_hold(id: String, cargo: Dictionary) -> bool:
	if not ships.has(id):
		return false
	var total := 0
	for commodity in cargo:
		if str(commodity).is_empty() or typeof(cargo[commodity]) != TYPE_INT or int(cargo[commodity]) < 0:
			return false
		total += int(cargo[commodity])
		if total > int(ships[id]["cargo_capacity"]):
			return false
	return true

func set_fuel_from_authoritative_result(id: String, value: float) -> bool:
	if not ships.has(id) or not is_finite(value):
		return false
	if value < 0.0 or value > float(ships[id]["fuel_capacity"]):
		return false
	ships[id]["fuel"] = value
	return true

func snapshot() -> Array:
	var ids := ships.keys()
	ids.sort()
	var result: Array = []
	for id in ids:
		result.append((ships[id] as Dictionary).duplicate(true))
	return result

func restore(records: Array) -> bool:
	var restored := {}
	for record in records:
		if not record is Dictionary:
			return false
		var id := str(record.get("id", ""))
		var ship_class := str(record.get("class", ""))
		var spec := Catalog.spec(ship_class)
		if id.is_empty() or restored.has(id) or spec.is_empty():
			return false
		var size := str(record.get("size", ""))
		if Catalog.size_tier(size) == 0:
			return false
		if str(record.get("faction_id", "")).is_empty() or str(record.get("system_id", "")).is_empty():
			return false
		if int(record.get("cargo_capacity", -1)) < 0 or not record.get("cargo", null) is Dictionary:
			return false
		var cargo: Dictionary = record["cargo"]
		var total := 0
		for commodity in cargo:
			if str(commodity).is_empty() or typeof(cargo[commodity]) != TYPE_INT or int(cargo[commodity]) < 0:
				return false
			total += int(cargo[commodity])
		# Rust ShipCargo::free saturates after a real refit; it does
		# not discard an existing cargo hold when capacity shrinks.
		if total > int(record["cargo_capacity"]) and not record.has("fitting"):
			return false
		# Old checkpoints may lack N51+N101; new-source ships carry
		# both components together.
		if record.has("fitting") != record.has("progression"):
			return false
		if record.has("fitting"):
			var fitting: Variant = record["fitting"]
			if not (fitting is Dictionary) or not (fitting.get("slots") is Dictionary) or not (fitting.get("derived") is Dictionary):
				return false
			var derived: Dictionary = ModuleCatalog.combine(fitting["slots"])
			if derived.is_empty() or fitting["derived"] != derived:
				return false
			var cap: int = roundi(float(spec["cargo_capacity"]) *
				float(derived["cargo_capacity_mult"]))
			if int(record["cargo_capacity"]) != cap:
				return false
			if not (record.get("speed_modifier") is float or record.get("speed_modifier") is int):
				return false
			var speed: float = float(record["speed_modifier"])
			if not is_finite(speed) or speed <= 0.0:
				return false
			if not (record.get("fuel_efficiency_mult") is float or record.get("fuel_efficiency_mult") is int):
				return false
			if not is_equal_approx(float(record["fuel_efficiency_mult"]),
					float(derived["fuel_efficiency_mult"])):
				return false
			if not is_equal_approx(float(record.get("comms_bonus", -1.0)),
					float(derived["comms_bonus"])):
				return false
			var progression: Variant = record["progression"]
			if not (progression is Dictionary):
				return false
			for k in ["level", "xp", "retrofit_points"]:
				if typeof(progression.get(k, null)) != TYPE_INT or int(progression[k]) < 0:
					return false
			if int(progression["level"]) < 1 or int(progression["level"]) > Progression.LEVEL_CAP or int(progression["xp"]) > Progression.U32_MAX or int(progression["retrofit_points"]) > Progression.U8_MAX:
				return false
			if progression.has("dirty") and typeof(progression["dirty"]) != TYPE_BOOL:
				return false
		var fuel := float(record.get("fuel", -1.0))
		var capacity := float(record.get("fuel_capacity", -1.0))
		if not is_finite(fuel) or not is_finite(capacity) or capacity <= 0.0 or fuel < 0.0 or fuel > capacity:
			return false
		if int(record.get("crew_size", -1)) < 0 or not record.get("crew_roles", null) is Array:
			return false
		if int(record["crew_size"]) != (record["crew_roles"] as Array).size():
			return false
		restored[id] = record.duplicate(true)
	ships = restored
	return true
