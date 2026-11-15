extends RefCounted
## N48: opt-in physical passenger manifest. No autonomous contract posting:
## frozen Rust population.rs explicitly disables unsupported passenger posts.
## This model owns ONLY passenger counts; caller must supply authoritative
## dock/ship-location facts and reconcile them before committing each action.
const BATCH_SIZE := 50
const MIN_SOURCE_POP := 5000
const MIN_SOURCE_SENTIMENT := 50

var populations: Dictionary = {}
var ships: Dictionary = {}
var receipts: Dictionary = {}

func configure(pop_state: Dictionary, ship_state: Dictionary) -> bool:
	if not populations.is_empty() or not ships.is_empty() or not receipts.is_empty():
		return false
	for id in pop_state:
		var p: Dictionary = pop_state[id]
		if str(id).is_empty() or str(p.get("location", "")).is_empty() or int(p.get("count", -1)) < 0 or int(p.get("sentiment", -1)) < 0 or int(p.get("sentiment", -1)) > 100:
			return false
	for id in ship_state:
		var s: Dictionary = ship_state[id]
		if str(id).is_empty() or int(s.get("capacity", -1)) < 0 or str(s.get("location", "")).is_empty() or not s.get("passengers", {}).is_empty():
			return false
	populations = pop_state.duplicate(true)
	ships = ship_state.duplicate(true)
	return true

func embark(receipt: String, pop_id: String, ship_id: String, dock_location: String, amount: int = BATCH_SIZE) -> bool:
	if receipt.is_empty() or receipts.has(receipt) or not populations.has(pop_id) or not ships.has(ship_id) or dock_location.is_empty():
		return false
	var p: Dictionary = populations[pop_id]
	var s: Dictionary = ships[ship_id]
	if not bool(s.get("docked", false)) or str(s.get("location", "")) != dock_location or str(p.get("location", "")) != dock_location:
		return false
	if amount <= 0 or amount > BATCH_SIZE or int(p["count"]) < MIN_SOURCE_POP or int(p["sentiment"]) < MIN_SOURCE_SENTIMENT or int(p["count"]) < amount:
		return false
	var occupied := 0
	for passenger in s.get("passengers", {}).values():
		occupied += int(passenger)
	if occupied + amount > int(s["capacity"]):
		return false
	var cargo: Dictionary = s.get("passengers", {}).duplicate()
	cargo[pop_id] = int(cargo.get(pop_id, 0)) + amount
	p["count"] = int(p["count"]) - amount
	s["passengers"] = cargo
	populations[pop_id] = p
	ships[ship_id] = s
	receipts[receipt] = {"action": "embark", "ship": ship_id, "pop": pop_id, "amount": amount}
	return true

func disembark(receipt: String, pop_id: String, ship_id: String, destination_id: String, dock_location: String, amount: int) -> bool:
	if receipt.is_empty() or receipts.has(receipt) or not populations.has(destination_id) or not ships.has(ship_id) or dock_location.is_empty():
		return false
	var p: Dictionary = populations[destination_id]
	var s: Dictionary = ships[ship_id]
	var cargo: Dictionary = s.get("passengers", {}).duplicate()
	if not bool(s.get("docked", false)) or str(s.get("location", "")) != dock_location or str(p.get("location", "")) != dock_location or amount <= 0 or int(cargo.get(pop_id, 0)) < amount:
		return false
	cargo[pop_id] = int(cargo[pop_id]) - amount
	if int(cargo[pop_id]) == 0:
		cargo.erase(pop_id)
	p["count"] = int(p["count"]) + amount
	s["passengers"] = cargo
	populations[destination_id] = p
	ships[ship_id] = s
	receipts[receipt] = {"action": "disembark", "ship": ship_id, "origin": pop_id, "destination": destination_id, "amount": amount}
	return true

func snapshot() -> Dictionary:
	return {"populations": populations.duplicate(true), "ships": ships.duplicate(true), "receipts": receipts.duplicate(true)}

func restore(data: Dictionary) -> bool:
	if not data.has_all(["populations", "ships", "receipts"]):
		return false
	var pp: Dictionary = data["populations"]
	var ss: Dictionary = data["ships"]
	var rr: Dictionary = data["receipts"]
	for p in pp.values():
		if not p is Dictionary or int(p.get("count", -1)) < 0 or str(p.get("location", "")).is_empty():
			return false
	for s in ss.values():
		if not s is Dictionary or int(s.get("capacity", -1)) < 0 or str(s.get("location", "")).is_empty():
			return false
		var total := 0
		for count in s.get("passengers", {}).values():
			if int(count) <= 0:
				return false
			total += int(count)
		if total > int(s["capacity"]):
			return false
	populations = pp.duplicate(true)
	ships = ss.duplicate(true)
	receipts = rr.duplicate(true)
	return true
