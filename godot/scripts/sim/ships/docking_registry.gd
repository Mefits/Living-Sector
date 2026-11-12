extends RefCounted
## Deterministic, authority-side docking reservations. No SceneTree/visual state.
## Rust reference: agents/ship/actions.rs RequestDock / Undock and apply-phase capacity.
const VERSION := 1
var facilities: Dictionary = {} # id -> {location, capacity, type}
var ships: Dictionary = {} # id -> {location, in_transit, docked_at}
var occupants: Dictionary = {} # facility id -> Array[String] (sorted)
var receipts: Dictionary = {} # operation key -> result snapshot

func register_facility(id: String, location: String, capacity: int, kind: String) -> bool:
	if id.is_empty() or location.is_empty() or capacity < 0 or facilities.has(id):
		return false
	facilities[id] = {"location": location, "capacity": capacity, "type": kind}
	occupants[id] = []
	return true

func register_ship(id: String, location: String, in_transit: bool = false) -> bool:
	if id.is_empty() or ships.has(id):
		return false
	ships[id] = {"location": location, "in_transit": in_transit, "docked_at": ""}
	return true

func request_dock(ship_id: String, operation_id: String, preferred_type: String = "") -> Dictionary:
	if operation_id.is_empty():
		return {"ok": false, "reason": "missing_operation_id"}
	if receipts.has(operation_id):
		return receipts[operation_id].duplicate(true)
	var result := _dock_once(ship_id, preferred_type)
	# Store both successes and failures: retry must use a fresh operation id.
	receipts[operation_id] = result.duplicate(true)
	return result

func _dock_once(ship_id: String, preferred_type: String) -> Dictionary:
	if not ships.has(ship_id):
		return {"ok": false, "reason": "unknown_ship"}
	var ship: Dictionary = ships[ship_id]
	if bool(ship.get("in_transit", false)) or String(ship.get("location", "")).is_empty():
		return {"ok": false, "reason": "in_transit"}
	if String(ship.get("docked_at", "")) != "":
		return {"ok": false, "reason": "already_docked"}
	var candidates: Array[String] = []
	for facility_id in facilities:
		var f: Dictionary = facilities[facility_id]
		if String(f["location"]) != String(ship["location"]):
			continue
		if preferred_type != "" and String(f["type"]) != preferred_type:
			continue
		if (occupants[facility_id] as Array).size() >= int(f["capacity"]):
			continue
		candidates.append(String(facility_id))
	# Stable choice: most available slots first, then lexical ID. Never depend on hash order.
	candidates.sort_custom(func(a: String, b: String) -> bool:
		var free_a: int = int(facilities[a]["capacity"]) - (occupants[a] as Array).size()
		var free_b: int = int(facilities[b]["capacity"]) - (occupants[b] as Array).size()
		return a < b if free_a == free_b else free_a > free_b
	)
	if candidates.is_empty():
		return {"ok": false, "reason": "no_available_dock"}
	var chosen: String = candidates[0]
	var members: Array = occupants[chosen]
	members.append(ship_id)
	members.sort()
	ship["docked_at"] = chosen
	return {"ok": true, "facility_id": chosen}

func undock(ship_id: String, operation_id: String) -> Dictionary:
	if operation_id.is_empty():
		return {"ok": false, "reason": "missing_operation_id"}
	if receipts.has(operation_id):
		return receipts[operation_id].duplicate(true)
	var result: Dictionary
	if not ships.has(ship_id):
		result = {"ok": false, "reason": "unknown_ship"}
	else:
		var ship: Dictionary = ships[ship_id]
		var dock: String = String(ship.get("docked_at", ""))
		if dock.is_empty():
			result = {"ok": false, "reason": "not_docked"}
		else:
			(occupants[dock] as Array).erase(ship_id)
			ship["docked_at"] = ""
			result = {"ok": true, "facility_id": dock}
	receipts[operation_id] = result.duplicate(true)
	return result

func begin_transit(ship_id: String) -> bool:
	if not ships.has(ship_id):
		return false
	var ship: Dictionary = ships[ship_id]
	if String(ship.get("docked_at", "")) != "" or bool(ship.get("in_transit", false)):
		return false
	ship["in_transit"] = true
	ship["location"] = ""
	return true

func arrive(ship_id: String, location: String) -> bool:
	if not ships.has(ship_id) or location.is_empty():
		return false
	var ship: Dictionary = ships[ship_id]
	if not bool(ship.get("in_transit", false)):
		return false
	ship["location"] = location
	ship["in_transit"] = false
	return true

func snapshot() -> Dictionary:
	return {"version": VERSION, "facilities": facilities.duplicate(true), "ships": ships.duplicate(true), "occupants": occupants.duplicate(true), "receipts": receipts.duplicate(true)}

func restore(data: Dictionary) -> bool:
	if int(data.get("version", -1)) != VERSION:
		return false
	for field in ["facilities", "ships", "occupants", "receipts"]:
		if not (data.get(field) is Dictionary):
			return false
	var next_facilities: Dictionary = data["facilities"].duplicate(true)
	var next_ships: Dictionary = data["ships"].duplicate(true)
	var next_occupants: Dictionary = data["occupants"].duplicate(true)
	for fid in next_facilities:
		var facility: Dictionary = next_facilities[fid]
		if int(facility.get("capacity", -1)) < 0 or not next_occupants.has(fid):
			return false
		var members: Array = next_occupants[fid]
		if members.size() > int(facility["capacity"]):
			return false
		var seen: Dictionary = {}
		for sid in members:
			if seen.has(sid) or not next_ships.has(sid):
				return false
			seen[sid] = true
			if String(next_ships[sid].get("docked_at", "")) != String(fid) or bool(next_ships[sid].get("in_transit", false)) or String(next_ships[sid].get("location", "")) != String(facility.get("location", "")):
				return false
	for sid in next_ships:
		var ship: Dictionary = next_ships[sid]
		var dock: String = String(ship.get("docked_at", ""))
		if dock != "" and (not next_occupants.has(dock) or not (next_occupants[dock] as Array).has(sid)):
			return false
	facilities = next_facilities
	ships = next_ships
	occupants = next_occupants
	receipts = data["receipts"].duplicate(true)
	return true
