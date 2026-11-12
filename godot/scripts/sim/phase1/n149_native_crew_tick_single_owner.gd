extends RefCounted
## N149 — original frozen Rust sim_core/src/agents/ship/mod.rs::tick_crew.
## SINGLE physical transition proposal; supersedes calling N72.step()+N138
## stages independently in Phase 2. No real ECS/credit/cargo mutations here.
## Phase2 engine chooses ONE atomic apply owner for the full proposed payload.
## Native source uses f32; GDScript floats are f64. Rounding parity needs
## runtime Rust-vs-Godot comparison before claiming VERIFIED.

const MAX_U32: int = 4294967295
const MAX_I64: int = 9223372036854775807
const MIN_I64: int = -9223372036854775807 - 1
const TASKS := ["idle", "piloting", "engineering", "trading", "loading",
	"unloading", "eating", "resting", "on_mission"]

const HUNGER_RATE_BASE: float = 1.0
const HUNGER_DOCKED_RECOVERY: float = 5.0
const FATIGUE_RATE_ACTIVE_BASE: float = 0.4
const FATIGUE_RATE_REST_BASE: float = -5.0
const FATIGUE_DOCKED_RECOVERY: float = 5.0
const HUNGER_MORALE_PENALTY: float = 60.0
const FATIGUE_MORALE_PENALTY: float = 70.0
const MORALE_CHECK_INTERVAL_BASE: int = 5
const MORALE_DECAY_BASE: float = 0.5
const MORALE_RECOVERY_DOCKED: float = 6.0
const MORALE_RECOVERY_RESTING: float = 8.0
const HUNGER_EAT_THRESHOLD: float = 55.0
const FATIGUE_REST_THRESHOLD: float = 65.0
const HUNGER_MEAL_REDUCTION: float = 25.0
const CREW_FOOD_PER_CREW_PER_MEAL: int = 1
const WAGE_INTERVAL_BASE: int = 50
const WAGE_PER_HEAD: int = 5
const WAGE_UNPAID_MORALE_DROP: float = 5.0

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func _numeric(v: Variant) -> bool:
	return typeof(v) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(v))

static func _valid(crew: Dictionary, economy: Dictionary, hold: Dictionary,
		ages: Dictionary, roles: Array) -> String:
	for key in ["size", "hunger", "morale", "fatigue", "health",
			"wages_credits", "current_task"]:
		if not crew.has(key):
			return "missing_crew:" + key
	if typeof(crew["size"]) != TYPE_INT or int(crew["size"]) < 0 or int(crew["size"]) > MAX_U32:
		return "invalid_crew_size"
	if typeof(crew["wages_credits"]) != TYPE_INT or int(crew["wages_credits"]) < 0:
		return "invalid_crew_wages"
	for field in ["hunger", "fatigue", "morale", "health"]:
		if not _numeric(crew[field]):
			return "nonfinite_crew:" + field
		if float(crew[field]) < 0.0 or float(crew[field]) > 100.0:
			return "crew_stat_out_of_bounds:" + field
	if not (crew["current_task"] is String) or str(crew["current_task"]) not in TASKS:
		return "unknown_crew_task"
	if typeof(economy.get("credits", null)) != TYPE_INT or not _numeric(economy.get("efficiency")):
		return "missing_real_ship_wallet_or_efficiency"
	for role in roles:
		if not (role is String):
			return "invalid_crew_role"
	for commodity in hold:
		if not (commodity is String) or typeof(hold[commodity]) != TYPE_INT or 				int(hold[commodity]) < 0 or int(hold[commodity]) > MAX_U32:
			return "invalid_native_hold"
	for commodity in ages:
		if not (commodity is String) or typeof(ages[commodity]) != TYPE_INT or int(ages[commodity]) < 0:
			return "invalid_native_cargo_age"
	return ""

static func primary_task(roles: Array, in_transit: bool) -> String:
	## The genuine Rust primary_task, NOT a made-up "all pilots pilot".
	if in_transit:
		if roles.has("pilot"):
			return "piloting"
		if roles.has("engineer"):
			return "engineering"
		if roles.has("trader"):
			return "trading"
		return "idle"
	if roles.has("trader"):
		return "trading"
	if roles.has("engineer"):
		return "engineering"
	return "idle"

static func core_step(ship: Dictionary, tick: int, tick_scale: float,
		tick_multiplier: int, skipped_ticks: int = 1) -> Dictionary:
	## Input is one genuine ECS snapshot:
	## {
	##  ship_id:String, crew:{size,hunger,morale,fatigue,health,wages_credits,
	##             current_task,dirty}, economy:{credits,efficiency},
	##  cargo:{commodity:int}, cargo_age:{commodity:tick},
	##  roles:[String], docked:bool, in_transit:bool
	## }
	##
	## IMPORTANT: World.tick_ships LOD gate decides whether to call here.
	## If not active, do not invoke core_step (use batch step fired map).
	for field in ["ship_id", "crew", "economy", "cargo", "cargo_age",
			"roles", "docked", "in_transit"]:
		if not ship.has(field):
			return _fail("missing_native_ship_fact:" + field)
	if not (ship["ship_id"] is String) or str(ship["ship_id"]).is_empty():
		return _fail("invalid_native_ship_identity")
	if not (ship["crew"] is Dictionary and ship["economy"] is Dictionary and 			ship["cargo"] is Dictionary and ship["cargo_age"] is Dictionary and ship["roles"] is Array and 			ship["docked"] is bool and ship["in_transit"] is bool):
		return _fail("invalid_native_ship_components")
	if tick < 0 or tick_multiplier < 0 or skipped_ticks < 1 or 			not is_finite(tick_scale) or tick_scale < 0.0:
		return _fail("invalid_native_tick_or_lod")
	var before_c: Dictionary = ship["crew"]
	var before_e: Dictionary = ship["economy"]
	var before_hold: Dictionary = ship["cargo"]
	var before_ages: Dictionary = ship["cargo_age"]
	var bad := _valid(before_c, before_e, before_hold, before_ages, ship["roles"])
	if bad != "":
		return _fail(bad)
	var c := before_c.duplicate(true)
	var e := before_e.duplicate(true)
	var hold := before_hold.duplicate(true)
	var ages := before_ages.duplicate(true)
	var stage_log: Array[String] = []
	var scale: float = tick_scale * float(skipped_ticks)
	if not is_finite(scale):
		return _fail("nonfinite_effective_lod_scale")
	var docked: bool = bool(ship["docked"])
	var in_transit: bool = bool(ship["in_transit"])
	var old_task: String = str(c["current_task"])
	# 1. Decay (no food or money effects). Note resting > docked > active
	# fatigue precedence; idle when not in transit has -1 even docked.
	var hunger_delta: float = -HUNGER_DOCKED_RECOVERY * scale if docked else HUNGER_RATE_BASE * scale
	c["hunger"] = clampf(float(c["hunger"]) + hunger_delta, 0.0, 100.0)
	var fatigue_delta: float = FATIGUE_RATE_ACTIVE_BASE
	if old_task == "resting":
		fatigue_delta = FATIGUE_RATE_REST_BASE
	elif old_task == "idle" and not in_transit:
		fatigue_delta = -1.0
	elif docked:
		fatigue_delta = -FATIGUE_DOCKED_RECOVERY
	c["fatigue"] = clampf(float(c["fatigue"]) + fatigue_delta * scale, 0.0, 100.0)
	stage_log.append("decay")
	# 2. Morale reads POST-decay hunger/fatigue and OLD task (before food).
	var morale_interval: int = MORALE_CHECK_INTERVAL_BASE * tick_multiplier
	if morale_interval > 0 and tick % morale_interval == 0:
		var penalty: float = 0.0
		if docked:
			if float(c["health"]) < 50.0:
				penalty = -2.0
		elif float(c["hunger"]) > HUNGER_MORALE_PENALTY:
			penalty = -3.0
		elif float(c["fatigue"]) > FATIGUE_MORALE_PENALTY:
			penalty = -2.0
		elif float(c["health"]) < 50.0:
			penalty = -4.0
		var recovery: float = 0.0
		if docked and old_task == "resting":
			recovery = MORALE_RECOVERY_RESTING
		elif docked or old_task == "resting":
			recovery = MORALE_RECOVERY_DOCKED
		var drift: float = -MORALE_DECAY_BASE if float(c["morale"]) > 50.0 else MORALE_DECAY_BASE
		c["morale"] = clampf(float(c["morale"]) + penalty + recovery + drift, 0.0, 100.0)
	stage_log.append("morale")
	# 3. Eating acts IMMEDIATELY on food, but goes to Eating even when
	# food absent or post-meal hunger dropped below threshold.
	var before_meal_hunger: float = float(c["hunger"])
	var food_debit: int = 0
	if before_meal_hunger > HUNGER_EAT_THRESHOLD:
		var needed: int = int(c["size"]) * CREW_FOOD_PER_CREW_PER_MEAL
		var available: int = int(hold.get("food", 0))
		if available >= needed:
			food_debit = needed
			# Rust removes cargo and cargo_age if Food stock has hit 0.
			var remains: int = available - needed
			if remains == 0:
				hold.erase("food")
				ages.erase("food")
			else:
				hold["food"] = remains
			c["hunger"] = maxf(0.0, float(c["hunger"]) - HUNGER_MEAL_REDUCTION)
		c["current_task"] = "eating"
	elif float(c["fatigue"]) > FATIGUE_REST_THRESHOLD:
		c["current_task"] = "resting"
	else:
		var needs_refresh: bool = (
			(old_task in ["eating", "resting"] and
			float(c["hunger"]) < HUNGER_EAT_THRESHOLD and float(c["fatigue"]) < FATIGUE_REST_THRESHOLD)
			or old_task == "idle"
			or (in_transit and old_task != "piloting"))
		if needs_refresh:
			c["current_task"] = primary_task(ship["roles"], in_transit)
	stage_log.append("food_then_role")
	# 4. Source checks real ship credits and i64 checked_add on PAID crew
	# wages. A failed payment reduces morale, never grants phantom wages.
	var owed: int = int(c["size"]) * WAGE_PER_HEAD
	var wage_debit: int = 0
	var unpaid_penalty: bool = false
	var wage_interval: int = WAGE_INTERVAL_BASE * tick_multiplier
	if wage_interval > 0 and tick % wage_interval == 0 and int(c["size"]) > 0:
		if int(e["credits"]) >= owed and int(c["wages_credits"]) <= MAX_I64 - owed:
			e["credits"] = int(e["credits"]) - owed
			c["wages_credits"] = int(c["wages_credits"]) + owed
			wage_debit = owed
		else:
			c["morale"] = maxf(0.0, float(c["morale"]) - WAGE_UNPAID_MORALE_DROP)
			unpaid_penalty = true
	stage_log.append("wages")
	# 5. Native ShipCrew::efficiency uses morale AFTER unpaid-wage penalty.
	e["efficiency"] = clampf(float(c["health"]) / 100.0 * 0.6
		+ float(c["morale"]) / 100.0 * 0.4, 0.1, 1.0)
	c["dirty"] = true
	stage_log.append("efficiency")
	var effects: Dictionary = {
		"food_delta": -food_debit, "ship_credits_delta": -wage_debit,
		"crew_savings_delta": wage_debit,
		"unpaid_wages": unpaid_penalty,
		"one_native_crew_tick": true
	}
	var projected := ship.duplicate(true)
	projected["crew"] = c
	projected["economy"] = e
	projected["cargo"] = hold
	projected["cargo_age"] = ages
	return {"ok": true, "ship_id": ship["ship_id"],
		"tick": tick, "stage_order": stage_log,
		"before": {
			"crew": before_c.duplicate(true), "economy": before_e.duplicate(true),
			"cargo": before_hold.duplicate(true), "cargo_age": before_ages.duplicate(true)},
		"projected_ship": projected, "effects": effects,
		"precondition": "actual_native_ECS_ship_state_must_still_match_before",
		"requires": "single_authoritative_crew_cargo_wallet_atomic_apply"}

static func batch_prepare(ships: Dictionary, fired: Dictionary, tick: int,
		tick_scale: float, tick_multiplier: int) -> Dictionary:
	## The original active LOD cursor is owned by N140/ShipTickRunner.
	## The batch must not process a ship not actually fired, nor run a
	## second N72 economy tick. Invalid input rejects the entire batch.
	if tick < 0 or tick_multiplier < 0 or not is_finite(tick_scale) or tick_scale < 0.0:
		return _fail("invalid_batch_clock")
	var proposals := {}
	var ids := ships.keys()
	ids.sort()
	for ship_id in ids:
		if not (ship_id is String) or not (ships[ship_id] is Dictionary):
			return _fail("invalid_ship_dictionary")
		if not fired.has(ship_id):
			continue
		var skipped = fired[ship_id]
		if typeof(skipped) != TYPE_INT or int(skipped) < 1:
			return _fail("invalid_ship_lod_skip")
		var fact: Dictionary = ships[ship_id]
		if str(fact.get("ship_id", "")) != str(ship_id):
			return _fail("native_ship_id_mismatch")
		var stage := core_step(fact, tick, tick_scale, tick_multiplier, int(skipped))
		if not bool(stage.get("ok", false)):
			return _fail("crew_step_failed:" + str(ship_id) + ":" + str(stage.get("reason", "")))
		proposals[ship_id] = stage
	# all-or-nothing for staging; the actual engine must also commit
	# exactly once per authoritative native tick across ALL touched ECS.
	return {"ok": true, "proposals": proposals, "fired_count": proposals.size(),
		"origin_unchanged": true}
