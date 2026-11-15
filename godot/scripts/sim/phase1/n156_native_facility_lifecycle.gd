extends RefCounted
## N156: frozen sim_core/agents/facility/mod.rs original physical facility
## lifecycle. Pure snapshot stages ONLY. One real ECS/N39 paid World owner.
## Source note: facility crew source no longer double-consumes Food; its
## morale is computed from real household satisfaction and paid WorkShift.
const CONDITION_DEGRADE: float = 0.0002
const REPAIR_BELOW: float = 0.8
const REPAIR_PER_TOOL: float = 0.01
const ABANDON_BELOW: float = 0.1
const ABANDON_TICKS: int = 200
const CREW_INTERVAL: int = 5
const DOCK_SWEEP_INTERVAL: int = 10
const REPAIR_INTERVAL: int = 20
const ABANDON_INTERVAL: int = 10
const MAX_U32: int = 4294967295

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func _numeric(v: Variant) -> bool:
	return typeof(v) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(v))

static func _valid_facility(f: Dictionary) -> bool:
	if not (f.get("id") is String and f.get("location_name") is String and \
			f.get("facility_type") is String and f.get("operations") is Dictionary and \
			f.get("storage") is Dictionary and f.get("lifecycle") is Dictionary):
		return false
	var ops: Dictionary = f["operations"]
	var life: Dictionary = f["lifecycle"]
	var storage: Dictionary = f["storage"]
	return _numeric(ops.get("condition")) and typeof(ops.get("credits")) == TYPE_INT and \
		typeof(life.get("abandon_counter")) == TYPE_INT and \
		life.get("abandoned") is bool and storage.get("reserves") is Dictionary and \
		storage.get("dock_queue") is Array

static func schedule(tick: int, multiplier: int) -> Dictionary:
	## Exactly the native tick_facilities_with_relations cadence, not
	## an invented single "daily" economy update.
	if tick < 0 or multiplier <= 0:
		return _fail("invalid_native_world_tick_multiplier")
	var due := {
		"employment_and_station_plan": tick % (5 * multiplier) == 0,
		"decay": true,
		"dock_queue": tick % (10 * multiplier) == 0,
		"facility_crew": tick % (CREW_INTERVAL * multiplier) == 0,
		"repair": tick % (REPAIR_INTERVAL * multiplier) == 0,
		"abandonment": tick % (ABANDON_INTERVAL * multiplier) == 0,
		"restock": tick % (20 * multiplier) == 0,
		"recipes": tick % (5 * multiplier) == 0,
		"mining": tick % (5 * multiplier) == 0,
		"delivery_contracts": tick % (50 * multiplier) == 0,
		"shipyard_modules": tick % (15 * multiplier) == 0,
		"station_feedback": tick % (5 * multiplier) == 0,
		"crew_missions": tick % (100 * multiplier) == 0
	}
	## Source stage order is NOT interchangeable: condition decay
	## happens before repair, repair before abandonment, abandonment
	## before restock and native recipes.
	return {"ok": true, "due": due,
		"order": ["build_facility_lod_gate",
			"refresh_employment_if_recipe_due",
			"degrade_condition",
			"dock_queue_sweep_if_due",
			"household_derived_crew_morale_if_due",
			"real_N39_paid_repair_then_tools_if_due",
			"abandonment_if_due",
			"real_N130_restock_if_due",
			"native_station_plan_if_recipe_due",
			"real_N39_recipes_and_mining_if_due_and_LOD_fired",
			"real_N104_facility_deliveries_if_due",
			"real_N154_paid_shipyard_modules_if_due",
			"native_station_feedback_if_recipe_due",
			"real_N104_crew_missions_if_due"],
		"requires": "one_exclusive_native_World_tick"}

static func start_tick(facilities: Array, ships: Dictionary,
		pop_satisfaction: Dictionary, tick: int, tick_scale: float,
		multiplier: int) -> Dictionary:
	## Actual LOD cursor is owned by N140/N39. This source step
	## advances only CHEAP global stages. N39 alone decides which
	## facilities fire actual recipe/mining updates.
	var schedule_result := schedule(tick, multiplier)
	if not bool(schedule_result.get("ok", false)):
		return schedule_result
	if not is_finite(tick_scale) or tick_scale < 0.0:
		return _fail("invalid_original_tick_scale")
	var due: Dictionary = schedule_result["due"]
	var next: Array = facilities.duplicate(true)
	var events: Array[Dictionary] = []
	var repair_candidates: Array[Dictionary] = []
	var ids := {}
	for f in next:
		if not (f is Dictionary) or not _valid_facility(f):
			return _fail("invalid_real_facility_projection")
		if ids.has(f["id"]):
			return _fail("duplicate_facility_id")
		ids[f["id"]] = true
	# 1. Source: condition degradation applies to all nonabandoned
	# facilities EVERY tick, including those skipped by LOD.
	for f in next:
		if bool(f["lifecycle"]["abandoned"]):
			continue
		f["operations"]["condition"] = maxf(0.0,
			float(f["operations"]["condition"]) - CONDITION_DEGRADE * tick_scale)
	# 1a. Live queue filtered by actual location AND non-null active
	# ShipEconomy.dock_attempt_start_tick, not by "docked" or promises.
	if bool(due["dock_queue"]):
		for f in next:
			var queue: Array = f["storage"]["dock_queue"]
			if queue.is_empty():
				continue
			var kept: Array = []
			for ship_id in queue:
				if not ships.has(ship_id) or not (ships[ship_id] is Dictionary):
					continue
				var ship: Dictionary = ships[ship_id]
				if ship.get("location_name", null) == f["location_name"] and \
						ship.get("dock_attempt_start_tick", null) != null:
					kept.append(ship_id)
			if kept.size() != queue.size():
				f["storage"]["dock_queue"] = kept
	# 1b. Source actual code uses latest paid-shift workers, NOT
	# an additional Food reserve debit or separate crew households.
	if bool(due["facility_crew"]):
		for f in next:
			var crew = f.get("crew", null)
			if not (crew is Dictionary):
				continue
			var shift = crew.get("work_shift", null)
			if not (shift is Dictionary) or not (shift.get("workers") is Array):
				continue
			var count: int = 0
			var weighted: float = 0.0
			for pair in shift["workers"]:
				# Rust WorkShift.workers serializes Vec<(String,u16)> as
				# ["population-id", count] tuples. A richer ECS adapter may
				# already expose {id,count}; accept both, NEVER fabricate.
				var pop_id: Variant = null
				var worker_count: Variant = null
				if pair is Array and pair.size()==2:
					pop_id=pair[0]
					worker_count=pair[1]
				elif pair is Dictionary:
					pop_id=pair.get("id",null)
					worker_count=pair.get("count",null)
				if not (pop_id is String) or typeof(worker_count)!=TYPE_INT or \
						int(worker_count)<0:
					return _fail("invalid_real_workshift_receipt")
				var n: int = int(worker_count)
				var food_sat: float = float(pop_satisfaction.get(pop_id, 0.0))
				if not is_finite(food_sat):
					return _fail("invalid_native_household_satisfaction")
				weighted += food_sat * float(n)
				count += n
			if count > 0:
				var morale: float = clampf(weighted / float(count), 0.0, 100.0)
				crew["morale"] = morale
				crew["hunger"] = 100.0 - morale
				crew["food_debt"] = 0.0
				crew["dirty"] = true
	# 2. Original self-repair candidate order is sorted by facility
	# identity. Paid N39 work_shift must be committed BEFORE Tools
	# reserve decrements and condition bump. At most one shift per tick.
	if bool(due["repair"]):
		for f in next:
			if bool(f["lifecycle"]["abandoned"]):
				continue
			var tools: float = float(f["storage"]["reserves"].get("tools", 0.0))
			if not is_finite(tools) or tools < 0.0:
				return _fail("invalid_real_tools_reserve")
			if float(f["operations"]["condition"]) < REPAIR_BELOW and tools >= 1.0:
				repair_candidates.append({"facility_id": f["id"],
					"tick": tick, "tools_required": 1.0,
					"requires": "actual_N39_pay_shift(producer=owner,Some(0))"})
		repair_candidates.sort_custom(func(a,b):
			return str(a["facility_id"]) < str(b["facility_id"]))
	return {"ok": true, "facilities_before_abandonment": next,
		"repair_candidates": repair_candidates, "events": events,
		"due": due, "stage_order": schedule_result["order"],
		"requires": "apply_paid_repairs_then_tick_abandonment_then_N130_restock"}

static func after_real_paid_repairs_and_abandonment(facilities: Array,
		paid_shift_receipts: Dictionary, tick: int, multiplier: int) -> Dictionary:
	## The real World owner applies exact completed WorkShift effects
	## and passes private receipts. This pure proposal only consumes
	## Tool reserves and updates condition; it never grants wages.
	var cycle := schedule(tick, multiplier)
	if not bool(cycle.get("ok", false)):
		return cycle
	var due: Dictionary = cycle["due"]
	var next: Array = facilities.duplicate(true)
	var events: Array[Dictionary] = []
	if bool(due["repair"]):
		for f in next:
			if not (f is Dictionary) or not _valid_facility(f):
				return _fail("invalid_facility")
			if bool(f["lifecycle"]["abandoned"]) or \
					float(f["operations"]["condition"]) >= REPAIR_BELOW:
				continue
			var tools: float = float(f["storage"]["reserves"].get("tools", 0.0))
			if tools < 1.0:
				continue
			var receipt = paid_shift_receipts.get(f["id"], null)
			if not (receipt is Dictionary) or not bool(receipt.get("paid_shift_committed",false)) or \
					not bool(receipt.get("trusted_internal_apply",false)) or \
					receipt.get("facility_id") != f["id"] or int(receipt.get("tick",-1)) != tick:
				continue
			f["storage"]["reserves"]["tools"] = tools - 1.0
			f["operations"]["condition"] = minf(1.0,
				float(f["operations"]["condition"]) + REPAIR_PER_TOOL)
			f["operations"]["dirty"] = true
			f["lifecycle"]["dirty"] = true
	# 3. Dying if condition<0.1 AND tools<1 AND credits<100
	# for 200 checks (NOT 200 wall ticks), 10×mult apart.
	if bool(due["abandonment"]):
		for f in next:
			if bool(f["lifecycle"]["abandoned"]):
				continue
			var life: Dictionary = f["lifecycle"]
			var ops: Dictionary = f["operations"]
			var reserve: float = float(f["storage"]["reserves"].get("tools",0.0))
			var dying: bool = float(ops["condition"]) < ABANDON_BELOW and \
				reserve < 1.0 and int(ops["credits"]) < 100
			if dying:
				life["abandon_counter"] = mini(MAX_U32,
					int(life["abandon_counter"]) + 1)
				if int(life["abandon_counter"]) >= ABANDON_TICKS and \
						not bool(life["abandoned"]):
					life["abandoned"] = true
					events.append({"kind":"facility_abandoned",
						"facility_id":f["id"],"facility_type":f["facility_type"],
						"location":f["location_name"], "condition":ops["condition"],
						"credits":ops["credits"]})
				life["dirty"] = true
			elif int(life["abandon_counter"]) > 0:
				life["abandon_counter"] = 0
				life["dirty"] = true
	return {"ok":true,"facilities":next,"events":events,
		"requires":"commit_one_ECS_stage_before_N130_restock_and_N39_recipe_owner"}

static func index_lod_fired(facilities: Array, fired: Dictionary) -> Dictionary:
	## N140 AgentLod.try_fire is real native source authority: this
	## only validates and forwards a physical firing receipt, and
	## never multiplies recipe yields by skipped ticks.
	var filtered := {}
	for f in facilities:
		if not (f is Dictionary) or not (f.get("id") is String):
			return _fail("invalid_real_facility_identity")
		var id: String = f["id"]
		if f.get("has_agent_lod", false) == false:
			filtered[id] = 1
		elif fired.has(id):
			if typeof(fired[id]) != TYPE_INT or int(fired[id]) < 1:
				return _fail("invalid_actual_AgentLod_try_fire")
			filtered[id] = int(fired[id])
	return {"ok":true,"fired":filtered,
		"requires":"N140_owns_AgentLod_cursor_and_N39_only_actual_paid_recipes"}
