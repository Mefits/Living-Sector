extends RefCounted
## N138 multi-ship welfare stages around authoritative N72 physical upkeep.
## Stages are PURE and must be called in exact native Rust order:
##   (1) N72 decay -> before_meals -> (2) N72 real cargo-food debit ->
##   (3) after_meals -> (4) N72 actual wages/penalty -> (5) after_wages.
## Never call an entire N72.step and then all three stages; that changes
## Rust's first priority morale check and risks double benefits.
const Welfare = preload("res://scripts/sim/phase1/n138_crew_welfare.gd")

static func _valid_ships(ships: Dictionary, phase: String) -> String:
	if ships.is_empty():
		return "no_authoritative_ship_snapshot"
	for id in ships.keys():
		var ship = ships[id]
		if not (id is String) or not (ship is Dictionary) or not (ship.get("crew") is Dictionary):
			return "malformed_ship_or_crew"
		for field in ["docked", "in_transit", "roles", "economy"]:
			if not ship.has(field):
				return "missing_authoritative_ship_context:" + str(field)
		if not (ship["roles"] is Array) or not (ship["economy"] is Dictionary):
			return "invalid_role_or_economy_shape"
		if phase == "after_wages" and not ship["economy"].has("credits"):
			return "missing_authoritative_ship_wallet"
	return ""

static func _apply(ships: Dictionary, phase: String, tick: int, multiplier: int) -> Dictionary:
	var problem := _valid_ships(ships, phase)
	if tick < 0 or multiplier < 1:
		problem = "invalid_tick_or_multiplier"
	if problem != "":
		return {"ok": false, "reason": problem, "ships": ships.duplicate(true), "phase": phase}
	var next := ships.duplicate(true)
	var ids := next.keys()
	ids.sort()
	for id in ids:
		var ship: Dictionary = next[id]
		var crew: Dictionary = ship["crew"]
		var result: Dictionary = {}
		match phase:
			"before_meals":
				result = Welfare.morale_after_decay(crew, bool(ship["docked"]), tick, multiplier)
				if bool(result.get("ok", false)):
					ship["crew"] = result["crew"]
					ship["n138_hunger_before_meal"] = float(result["crew"]["hunger"])
			"after_meals":
				if not ship.has("n138_hunger_before_meal"):
					return {"ok": false, "reason": "missing_pre_meal_hunger:" + str(id),
						"ships": ships.duplicate(true), "phase": phase}
				result = Welfare.task_after_meal(crew, ship["roles"], bool(ship["in_transit"]),
					float(ship["n138_hunger_before_meal"]))
				if bool(result.get("ok", false)):
					ship["crew"] = result["crew"]
					ship.erase("n138_hunger_before_meal")
			"after_wages":
				result = Welfare.economy_efficiency_after_wages(crew, ship["economy"])
				if bool(result.get("ok", false)):
					ship["economy"] = result["economy"]
			_:
				return {"ok": false, "reason": "invalid_stage", "ships": ships.duplicate(true), "phase": phase}
		if not bool(result.get("ok", false)):
			# Fail atomically: reject ALL staged changes in the batch.
			return {"ok": false, "reason": "invalid_crew:" + str(id) + ":" + str(result.get("reason", "")),
				"ships": ships.duplicate(true), "phase": phase}
		next[id] = ship
	return {"ok": true, "reason": "", "ships": next, "phase": phase}

static func before_meals(post_decay_ships: Dictionary, tick: int, multiplier: int) -> Dictionary:
	## Rust tick_crew phase 2, must read hunger/fatigue AFTER decay.
	return _apply(post_decay_ships, "before_meals", tick, multiplier)

static func after_meals(post_food_ships: Dictionary, tick: int, multiplier: int) -> Dictionary:
	## Rust tick_crew phase 3, MUST use physically reduced hunger, if any.
	return _apply(post_food_ships, "after_meals", tick, multiplier)

static func after_wages(post_pay_ships: Dictionary, tick: int, multiplier: int) -> Dictionary:
	## Rust tick_crew phase 5, sees unpaid-wage morale penalty if any.
	return _apply(post_pay_ships, "after_wages", tick, multiplier)

static func status(ships: Dictionary) -> Array[Dictionary]:
	## Read-only observer projections; never a second labor or economy ledger.
	var rows: Array[Dictionary] = []
	var ids := ships.keys()
	ids.sort()
	for id in ids:
		var ship = ships[id]
		if not (ship is Dictionary) or not (ship.get("crew") is Dictionary):
			continue
		var crew: Dictionary = ship["crew"]
		var efficiency: float = Welfare.efficiency(crew)
		rows.append({"ship_id": str(id), "task": str(crew.get("current_task", "")),
			"morale": float(crew.get("morale", 0.0)),
			"fatigue": float(crew.get("fatigue", 0.0)),
			"hunger": float(crew.get("hunger", 0.0)),
			"efficiency": efficiency,
			"needs_shore_leave": Welfare.needs_shore_leave(crew),
			"shore_leave_complete": Welfare.shore_leave_complete(crew),
			"legacy_rest_goal": Welfare.legacy_rest_goal_needed(crew)})
	return rows
