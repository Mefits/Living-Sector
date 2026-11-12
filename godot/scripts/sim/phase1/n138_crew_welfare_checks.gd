extends RefCounted
## N138 code-only source fixtures: executed only with Phase-2 Godot parser/runtime.
const Welfare = preload("res://scripts/sim/phase1/n138_crew_welfare.gd")
const Batch = preload("res://scripts/sim/phase1/n138_crew_welfare_batch.gd")

static func _crew(task: String = "idle", morale: float = 50.0) -> Dictionary:
	return {"size": 5, "current_task": task, "hunger": 40.0, "fatigue": 30.0,
		"morale": morale, "health": 100.0, "wages_credits": 0, "dirty": false}

static func _ship(id: String = "s") -> Dictionary:
	return {"crew": _crew(), "roles": ["pilot", "trader", "engineer"],
		"in_transit": true, "docked": false,
		"economy": {"credits": 100, "efficiency": 0.0}, "cargo": {"food": 10},
		"id": id}

static func run() -> Dictionary:
	var errors: Array[String] = []
	# Rust: hunger penalty takes precedence over fatigue and damaged health.
	var hungry := _crew("piloting", 60.0)
	hungry["hunger"] = 70.0
	hungry["fatigue"] = 90.0
	hungry["health"] = 20.0
	var result := Welfare.morale_after_decay(hungry, false, 5, 1)
	if not bool(result["ok"]) or not is_equal_approx(float(result["crew"]["morale"]), 56.5):
		errors.append("hunger_penalty_precedence")
	# Off-station resting gets 6 full points; docked resting 8.
	hungry["current_task"] = "resting"
	hungry["morale"] = 50.0
	result = Welfare.morale_after_decay(hungry, false, 5, 1)
	if not is_equal_approx(float(result["crew"]["morale"]), 53.5):
		errors.append("off_station_rest_recovery")
	hungry["morale"] = 49.0
	result = Welfare.morale_after_decay(hungry, true, 5, 1)
	if not is_equal_approx(float(result["crew"]["morale"]), 55.5):
		errors.append("docked_rest_recovery_and_health_penalty")
	# Wage/food changes must NEVER originate from these pure welfare stages.
	var original := {"s": _ship()}
	var stage := Batch.before_meals(original, 6, 1)
	if not bool(stage["ok"]) or original["s"]["crew"]["dirty"] or 		int(stage["ships"]["s"]["economy"]["credits"]) != 100:
		errors.append("before_meal_purity")
	if not is_equal_approx(float(stage["ships"]["s"]["crew"]["morale"]), 50.0):
		errors.append("cadence_does_not_mint_morale")
	# The task after meal reads ACTUALLY observed hunger, not anticipated food.
	var post_meal := stage["ships"].duplicate(true)
	post_meal["s"]["crew"]["hunger"] = 55.0
	post_meal["s"]["crew"]["current_task"] = "eating"
	var after := Batch.after_meals(post_meal, 6, 1)
	if str(after["ships"]["s"]["crew"]["current_task"]) != "eating":
		errors.append("strict_food_threshold_retains_existing_task")
	post_meal["s"]["crew"]["hunger"] = 54.0
	after = Batch.after_meals(post_meal, 6, 1)
	if str(after["ships"]["s"]["crew"]["current_task"]) != "piloting":
		errors.append("returns_to_piloting_after_meal")
	# Rust enters Eating from the BEFORE-meal threshold even if Food heals hunger.
	var before_food := {"s": _ship()}
	before_food["s"]["crew"]["hunger"] = 70.0
	var prepared := Batch.before_meals(before_food, 6, 1)
	var eaten := prepared["ships"].duplicate(true)
	eaten["s"]["crew"]["hunger"] = 45.0
	var still_eating := Batch.after_meals(eaten, 6, 1)
	if str(still_eating["ships"]["s"]["crew"]["current_task"]) != "eating":
		errors.append("eating_branch_must_use_pre_meal_hunger")
	if still_eating["ships"]["s"].has("n138_hunger_before_meal"):
		errors.append("ephemeral_hunger_token_must_not_persist")
	var shore := _crew("idle", 49.9)
	if not Welfare.needs_shore_leave(shore) or Welfare.shore_leave_complete(shore):
		errors.append("shore_leave_threshold")
	shore["morale"] = 100.0
	if Welfare.needs_shore_leave(shore) or not Welfare.shore_leave_complete(shore):
		errors.append("shore_leave_completion")
	var reduced := _crew("trading", 0.0)
	reduced["health"] = 0.0
	if not is_equal_approx(Welfare.efficiency(reduced), 0.1):
		errors.append("efficiency_floor")
	if Welfare.primary_task(["pilot", "trader"], false) != "trading" or 		Welfare.primary_task(["engineer", "pilot"], true) != "piloting":
		errors.append("roles_and_transit_priority")
	var unpaid := {"s": _ship()}
	unpaid["s"]["crew"]["morale"] = 10.0
	var with_eff := Batch.after_wages(unpaid, 50, 1)
	if int(with_eff["ships"]["s"]["economy"]["credits"]) != 100 or 		not is_equal_approx(float(with_eff["ships"]["s"]["economy"]["efficiency"]), 0.64):
		errors.append("wages_must_be_external_efficiency_propagates")
	var broken := {"a": _ship("a"), "b": _ship("b")}
	broken["b"]["crew"]["health"] = 999.0
	var rejected := Batch.before_meals(broken, 5, 1)
	if bool(rejected["ok"]) or rejected["ships"] != broken:
		errors.append("atomic_batch_rejection")
	if Welfare.dock_wait_budget(_crew("idle", 39.0), false, 2) != 60 or 		Welfare.dock_wait_budget(_crew("idle", 39.0), true, 2) != 300:
		errors.append("dock_wait_contract_priority")
	return {"ok": errors.is_empty(), "errors": errors}
