extends RefCounted
## N72 CODE_UNVERIFIED. Frozen Rust agents/ship/mod.rs tick_crew.
## Aggregated ship crew; cargo food is consumed physically; wages transfer to crew savings.
const HUNGER_RATE := 1.0
const HUNGER_DOCKED_RECOVERY := 5.0
const FATIGUE_ACTIVE := 0.4
const FATIGUE_REST := -5.0
const FATIGUE_DOCKED := -5.0
const EAT_THRESHOLD := 55.0
const REST_THRESHOLD := 65.0
const MORALE_CHECK_BASE := 5
const WAGE_INTERVAL_BASE := 50
const WAGE_PER_HEAD := 5
const FOOD_PER_CREW_PER_MEAL := 1
const HUNGER_MEAL_REDUCTION := 25.0
var _ships: Dictionary = {}
var _last_tick := -1

func import_ships(ships: Dictionary) -> bool:
	if not _ships.is_empty() or ships.is_empty() or not _valid(ships):
		return false
	_ships = ships.duplicate(true)
	return true

func step(tick: int, scale: float, multiplier: int) -> Dictionary:
	if tick < 0 or tick <= _last_tick or multiplier < 1 or not scale.is_finite() or scale < 0.0 or not _valid(_ships):
		return {"ok": false, "reason": "invalid_or_replayed"}
	var next := _ships.duplicate(true)
	var events: Array = []
	var ids := next.keys()
	ids.sort()
	for id in ids:
		var ship: Dictionary = next[id]
		var crew: Dictionary = ship.crew
		var hunger_delta := -HUNGER_DOCKED_RECOVERY if ship.docked else HUNGER_RATE
		crew.hunger = clampf(float(crew.hunger) + hunger_delta * scale, 0.0, 100.0)
		var fatigue_delta := FATIGUE_REST if crew.task == "resting" else (-1.0 if crew.task == "idle" and not ship.in_transit else (FATIGUE_DOCKED if ship.docked else FATIGUE_ACTIVE))
		crew.fatigue = clampf(float(crew.fatigue) + fatigue_delta * scale, 0.0, 100.0)
		if tick % (MORALE_CHECK_BASE * multiplier) == 0:
			var penalty := 0.0
			if ship.docked:
				penalty = -2.0 if float(crew.health) < 50.0 else 0.0
			elif float(crew.hunger) > 60.0:
				penalty = -3.0
			elif float(crew.fatigue) > 70.0:
				penalty = -2.0
			elif float(crew.health) < 50.0:
				penalty = -4.0
			crew.morale = clampf(float(crew.morale) + penalty, 0.0, 100.0)
		if float(crew.hunger) > EAT_THRESHOLD:
			var needed := int(crew.size) * FOOD_PER_CREW_PER_MEAL
			if needed > 0 and int(ship.food) >= needed:
				ship.food = int(ship.food) - needed
				crew.hunger = maxf(0.0, float(crew.hunger) - HUNGER_MEAL_REDUCTION)
				events.append({"ship": id, "kind": "ate", "food": needed, "tick": tick})
			crew.task = "eating"
		elif float(crew.fatigue) > REST_THRESHOLD:
			crew.task = "resting"
		elif crew.task == "eating" or crew.task == "resting" or crew.task == "idle":
			crew.task = "piloting" if ship.in_transit else "idle"
		if tick % (WAGE_INTERVAL_BASE * multiplier) == 0 and int(crew.size) > 0:
			var owed := WAGE_PER_HEAD * int(crew.size)
			if int(ship.credits) >= owed:
				ship.credits = int(ship.credits) - owed
				crew.wages_credits = int(crew.wages_credits) + owed
				events.append({"ship": id, "kind": "wages", "credits": owed, "tick": tick})
			else:
				crew.morale = maxf(0.0, float(crew.morale) - 5.0)
		ship.crew = crew
		next[id] = ship
	_ships = next
	_last_tick = tick
	return {"ok": true, "events": events}

func snapshot() -> Dictionary:
	return {"version": 1, "last_tick": _last_tick, "ships": _ships.duplicate(true)}

func restore(data: Dictionary) -> bool:
	if int(data.get("version", -1)) != 1 or typeof(data.get("last_tick")) != TYPE_INT or typeof(data.get("ships")) != TYPE_DICTIONARY or not _valid(data.ships):
		return false
	_ships = data.ships.duplicate(true)
	_last_tick = data.last_tick
	return true

func _valid(ships: Dictionary) -> bool:
	for id in ships:
		var s = ships[id]
		if typeof(id) != TYPE_STRING or typeof(s) != TYPE_DICTIONARY:
			return false
		for k in ["crew", "food", "credits", "docked", "in_transit"]:
			if not s.has(k):
				return false
		if int(s.food) < 0 or int(s.credits) < 0 :
			return false
		var c = s.crew
		if typeof(c) != TYPE_DICTIONARY:
			return false
		for k in ["size", "hunger", "fatigue", "morale", "health", "task", "wages_credits"]:
			if not c.has(k):
				return false
		if int(c.size) < 0 or int(c.wages_credits) < 0:
			return false
	return true
