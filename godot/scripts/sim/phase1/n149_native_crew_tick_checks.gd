extends RefCounted
## N149 source-derived 5-stage native aggregated crew tick scenarios.
## Checks AUTHORED but not run: Godot parser/headless reserved for Phase2.
const Tick = preload("res://scripts/sim/phase1/n149_native_crew_tick_single_owner.gd")
const Basics = preload("res://scripts/sim/phase1/n149_native_ship_components_basics.gd")

static func _expect(errors: Array[String], passed: bool, label: String) -> void:
	if not passed:
		errors.append(label)

static func _near(actual: Variant, expected: float) -> bool:
	return absf(float(actual) - expected) < 0.0001

static func _ship(id: String = "ship-a") -> Dictionary:
	return {
		"ship_id": id, "docked": false, "in_transit": true,
		"roles": ["pilot", "engineer", "trader"],
		"crew": {"size": 2, "hunger": 60.0, "fatigue": 70.0,
			"morale": 60.0, "health": 50.0, "current_task": "piloting",
			"wages_credits": 0, "dirty": false},
		"economy": {"credits": 100, "efficiency": 1.0},
		"cargo": {"food": 3, "ore": 9},
		"cargo_age": {"food": 10, "ore": 15}
	}

static func run() -> Dictionary:
	var errors: Array[String] = []
	var original := _ship()
	var before := original.duplicate(true)
	var stage := Tick.core_step(original, 50, 1.0, 1)
	_expect(errors, bool(stage.get("ok", false)), "one_native_crew_tick_valid")
	if bool(stage.get("ok", false)):
		var after: Dictionary = stage["projected_ship"]
		_expect(errors, stage["stage_order"] == [
			"decay", "morale", "food_then_role", "wages", "efficiency"],
			"true_rust_crew_phase_order")
		_expect(errors, _near(after["crew"]["hunger"], 36.0)
			and _near(after["crew"]["fatigue"], 70.4)
			and _near(after["crew"]["morale"], 56.5),
			"postdecay_morale_before_crew_ate_and_food_completes")
		_expect(errors, str(after["crew"]["current_task"]) == "eating"
			and int(after["cargo"]["food"]) == 1,
			"eating_task_persists_even_after_satisfied_hunger")
		_expect(errors, after["cargo_age"]["food"] == 10 and after["cargo_age"]["ore"] == 15,
			"preserve_origin_age_when_food_not_exhausted")
		_expect(errors, int(after["economy"]["credits"]) == 90
			and int(after["crew"]["wages_credits"]) == 10
			and _near(after["economy"]["efficiency"], 0.526),
			"wage_reallocation_then_efficiency_uses_postwage_morale")
		_expect(errors, int(stage["effects"]["food_delta"]) == -2
			and int(stage["effects"]["ship_credits_delta"]) == -10
			and int(stage["effects"]["crew_savings_delta"]) == 10,
			"single_atomic_real_cargo_and_credit_conservation")
		_expect(errors, original == before,
			"preparation_must_not_mutate_real_Rust_ship_world")
	var scarce := _ship()
	scarce["cargo"]["food"] = 1
	scarce["economy"]["credits"] = 0
	var broke := Tick.core_step(scarce, 50, 1.0, 1)
	_expect(errors, bool(broke["ok"])
		and int(broke["projected_ship"]["cargo"]["food"]) == 1
		and int(broke["projected_ship"]["crew"]["wages_credits"]) == 0
		and _near(broke["projected_ship"]["crew"]["morale"], 51.5)
		and bool(broke["effects"]["unpaid_wages"]),
		"missing_meal_and_unpaid_wage_sting_without_fabricated_food")
	var zero_food := _ship()
	zero_food["cargo"]["food"] = 2
	var ate_all := Tick.core_step(zero_food, 5, 1.0, 1)
	_expect(errors, bool(ate_all["ok"])
		and not ate_all["projected_ship"]["cargo"].has("food")
		and not ate_all["projected_ship"]["cargo_age"].has("food"),
		"Rust_meal_depletes_last_food_and_removes_cargo_age")
	var rested := _ship()
	rested["docked"] = true
	rested["in_transit"] = false
	rested["crew"]["hunger"] = 70.0
	rested["crew"]["fatigue"] = 80.0
	rested["crew"]["morale"] = 45.0
	rested["crew"]["health"] = 100.0
	rested["crew"]["current_task"] = "resting"
	rested["cargo"] = {"food": 1}
	rested["cargo_age"] = {"food": 25}
	var docked := Tick.core_step(rested, 5, 1.0, 1)
	_expect(errors, bool(docked["ok"])
		and _near(docked["projected_ship"]["crew"]["hunger"], 65.0)
		and _near(docked["projected_ship"]["crew"]["fatigue"], 75.0)
		and _near(docked["projected_ship"]["crew"]["morale"], 53.5)
		and docked["projected_ship"]["crew"]["current_task"] == "eating",
		"docked_rest_old_task_controls_morale_then_unsupplied_meal")
	var offstation := rested.duplicate(true)
	offstation["docked"] = false
	offstation["crew"]["health"] = 40.0
	var unrested := Tick.core_step(offstation, 5, 1.0, 1)
	_expect(errors, bool(unrested["ok"])
		and _near(unrested["projected_ship"]["crew"]["morale"], 48.5),
		"offstation_hunger_penalty_takes_priority_over_fatigue_and_health")
	var boundary := _ship()
	boundary["crew"]["hunger"] = 54.0
	boundary["crew"]["fatigue"] = 64.0
	boundary["crew"]["current_task"] = "eating"
	var exact := Tick.core_step(boundary, 3, 1.0, 1)
	_expect(errors, bool(exact["ok"])
		and exact["projected_ship"]["crew"]["current_task"] == "eating",
		"Rust_strict_lower_bound_hysteresis_keeps_Eating_at_55")
	var roles := _ship()
	roles["docked"] = true
	roles["in_transit"] = false
	roles["crew"]["hunger"] = 5.0
	roles["crew"]["fatigue"] = 5.0
	roles["crew"]["current_task"] = "idle"
	var trader := Tick.core_step(roles, 3, 1.0, 1)
	_expect(errors, bool(trader["ok"])
		and trader["projected_ship"]["crew"]["current_task"] == "trading",
		"stationary_crew_role_priority_is_trader_not_pilot")
	roles["docked"] = false
	roles["in_transit"] = true
	var pilot := Tick.core_step(roles, 3, 1.0, 1)
	_expect(errors, bool(pilot["ok"])
		and pilot["projected_ship"]["crew"]["current_task"] == "piloting",
		"intransit_pilot_has_priority")
	var saved := _ship()
	saved["crew"]["wages_credits"] = Tick.MAX_I64
	var over := Tick.core_step(saved, 50, 0.0, 1)
	_expect(errors, bool(over["ok"])
		and int(over["projected_ship"]["economy"]["credits"]) == 100
		and int(over["projected_ship"]["crew"]["wages_credits"]) == Tick.MAX_I64
		and bool(over["effects"]["unpaid_wages"]),
		"Rust_checked_add_wages_overflow_fails_closed_no_credit_debit")
	var skip := _ship()
	skip["crew"]["hunger"] = 10.0
	skip["crew"]["fatigue"] = 10.0
	var offscreen := Tick.batch_prepare({"ship-a":skip,"ship-b":_ship("ship-b")},
		{"ship-a":4}, 6, 0.25, 1)
	_expect(errors, bool(offscreen.get("ok", false))
		and int(offscreen["fired_count"]) == 1
		and _near(offscreen["proposals"]["ship-a"]["projected_ship"]["crew"]["hunger"], 11.0),
		"LOD_skipped_ticks_scale_welfare_without_touching_offscreen_ship")
	var blocked := Tick.batch_prepare({"ship-a":skip,"ship-b":_ship("ship-b")},
		{"ship-b":0}, 6, 1.0, 1)
	_expect(errors, not bool(blocked["ok"]) and skip["crew"]["hunger"] == 10.0,
		"invalid_LOD_rejects_whole_batch_without_partial_credit_apply")
	var inspect := Basics.cargo_used_and_free({"ore":30,"food":10}, 35)
	_expect(errors, bool(inspect["ok"]) and int(inspect["used"]) == 40
		and int(inspect["free"]) == 0,
		"native_ShipCargo_used_and_saturating_free")
	var cargo_error := Basics.cargo_used_and_free({"food":Basics.MAX_U32,"ice":1},Basics.MAX_U32)
	_expect(errors, not bool(cargo_error["ok"]),
		"u32_overflow_cargo_is_not_falsely_reported_as_free_storage")
	var fraction := Basics.fuel_fraction(15.0, 10.0)
	var no_tank := Basics.fuel_fraction(10.0, 0.0)
	_expect(errors, bool(fraction["ok"]) and _near(fraction["fraction"], 1.5)
		and bool(no_tank["ok"]) and _near(no_tank["fraction"], 0.0),
		"native_ShipFuel_fraction_does_not_artificially_clamp_tanks")
	return {"ok": errors.is_empty(), "errors": errors}
