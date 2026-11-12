extends RefCounted
## N148 — source-derived check scenarios, prepared for Phase-2 Godot runtime.
## These tests are AUTHORED ONLY. They were not run in the current session.
const Life = preload("res://scripts/sim/phase1/n148_native_ship_lifecycle.gd")
const Queue = preload("res://scripts/sim/phase1/n148_native_ship_retirement_queue.gd")
const Wire = preload("res://scripts/sim/phase1/n148_native_ship_wire_snapshot.gd")

static func _expect(errors: Array[String], condition: bool, label: String) -> void:
	if not condition:
		errors.append(label)

static func _ship(credits: int, cargo_used: int = 0, current_goal: String = "idle") -> Dictionary:
	return {"ship_entity": "ecs:42", "current_goal": current_goal,
		"credits": credits, "cargo_used": cargo_used, "active_contract_id": null}

static func _wire() -> Dictionary:
	return {"identity": {"id":"ship-alpha","name":"Alpha",
			"class":"freighter","faction_id":"f1","size":"medium"},
		"position":{"system_id":"sol","location_name":"earth-station",
			"docked_at":"station-1","coordinates":{"x":12.5,"y":-5.0}},
		"transit":null,
		"cargo":{"food":8},"cargo_capacity":30,
		"fuel":9.0,"fuel_capacity":20.0,"credits":450,
		"ai":{"current_goal":"idle","current_bt_action":null},
		"lifecycle":{"broke_strikes":1,"hoard_strikes":0,"idle_ticks":120,"dirty":true},
		"crew":{"size":3,"morale":49.6,"fatigue":78.4,
			"hunger":55.5,"health":100.0,"current_task":"eating",
			"wages_credits":120},
		"skills":{"navigation":40,"engineering":30,"trading":40,"combat":20},
		"fitting":null,"progression":{"level":2,"xp":120,"retrofit_points":1,
			"next_level_threshold":200},
		"active_contract_id":null,"faction_reputation":{}}

static func run() -> Dictionary:
	var errors: Array[String] = []
	var idle := Life.default_lifecycle()
	var ship := _ship(100)
	var before := idle.duplicate(true)
	var first := Life.lifecycle_step(idle, ship, 499, 1)
	_expect(errors, bool(first.get("ok", false)) and int(first["lifecycle"]["idle_ticks"]) == 1
		and int(first["lifecycle"]["broke_strikes"]) == 0,
		"idle_ticks_once_before_native_500_tick_strike")
	_expect(errors, idle == before, "no_mutation_of_native_lifecycle_argument")
	var crossed := Life.lifecycle_step(first["lifecycle"], ship, 500, 1)
	_expect(errors, int(crossed["lifecycle"]["broke_strikes"]) == 1
		and crossed["commands"].is_empty(), "bankruptcy_first_strike_at_500")
	var at_2 := Life.lifecycle_step(crossed["lifecycle"], ship, 1000, 1)
	var at_3 := Life.lifecycle_step(at_2["lifecycle"], ship, 1500, 1)
	_expect(errors, at_3["commands"].size() == 1
		and at_3["commands"][0]["reason"] == "bankruptcy"
		and int(at_3["lifecycle"]["broke_strikes"]) == 3,
		"three_periodic_broke_strikes_emit_decommission")
	var income := _ship(5000)
	var restored := Life.lifecycle_step(at_3["lifecycle"], income, 2000, 1)
	_expect(errors, int(restored["lifecycle"]["broke_strikes"]) == 0,
		"exact_5000_credit_recovery_resets_broke")
	var cargo := Life.lifecycle_step(crossed["lifecycle"], _ship(100, 1), 1000, 1)
	_expect(errors, int(cargo["lifecycle"]["broke_strikes"]) == 1,
		"cargo_prevents_new_broke_strike_but_does_not_reset")
	var employed := _ship(100)
	employed["active_contract_id"] = "contract-1"
	var contract := Life.lifecycle_step(crossed["lifecycle"], employed, 1000, 1)
	_expect(errors, int(contract["lifecycle"]["broke_strikes"]) == 1,
		"active_contract_prevents_broke_strike")
	var skipped := Life.lifecycle_step(crossed["lifecycle"], ship, 1500, 1, false)
	_expect(errors, int(skipped["lifecycle"]["broke_strikes"]) == 1
		and skipped["lifecycle"] == crossed["lifecycle"] and skipped["commands"].is_empty(),
		"offscreen_lod_does_not_advance_strike_cursor")
	var zero_multiplier := Life.lifecycle_step(crossed["lifecycle"], ship, 1500, 0)
	_expect(errors, int(zero_multiplier["lifecycle"]["broke_strikes"]) == 1,
		"multiplier_zero_has_no_division_by_zero")
	var scaled := Life.lifecycle_step(crossed["lifecycle"], ship, 500, 2)
	_expect(errors, int(scaled["lifecycle"]["broke_strikes"]) == 1,
		"strike_cadence_is_500_times_multiplier")
	var scaled_due := Life.lifecycle_step(crossed["lifecycle"], ship, 1000, 2)
	_expect(errors, int(scaled_due["lifecycle"]["broke_strikes"]) == 2,
		"strike_due_at_exact_world_tick_scale")
	var hoard := Life.default_lifecycle()
	hoard["idle_ticks"] = 500
	var rich := _ship(200001)
	var hoard_1 := Life.lifecycle_step(hoard, rich, 500, 1)
	_expect(errors, int(hoard_1["lifecycle"]["hoard_strikes"]) == 1,
		"hoard_strike_requires_idle_strictly_greater_than_500")
	var hoard_2 := Life.lifecycle_step(hoard_1["lifecycle"], rich, 1000, 1)
	var hoard_3 := Life.lifecycle_step(hoard_2["lifecycle"], rich, 1500, 1)
	_expect(errors, hoard_3["commands"].size() == 1
		and hoard_3["commands"][0]["reason"] == "stagnation",
		"rich_ship_three_hoard_checks_trigger_stagnation")
	var not_rich := Life.lifecycle_step(hoard_1["lifecycle"], _ship(200000), 1000, 1)
	_expect(errors, int(not_rich["lifecycle"]["hoard_strikes"]) == 1,
		"hoard_strikes_do_not_decay_at_strict_credit_threshold")
	var recovered := Life.lifecycle_step(hoard_1["lifecycle"], _ship(100), 1000, 1)
	_expect(errors, int(recovered["lifecycle"]["hoard_strikes"]) == 1,
		"broke_strikes_do_not_erase_hoard_history")
	var delivered := Life.after_confirmed_delivery(hoard_3["lifecycle"],
		{"trusted_internal_apply":true,"delivery_succeeded":true,
			"ship_entity":"ecs:42"})
	_expect(errors, bool(delivered["ok"])
		and int(delivered["lifecycle"]["hoard_strikes"]) == 0
		and int(delivered["lifecycle"]["idle_ticks"]) > 500,
		"confirmed_delivery_clears_only_hoard_strikes")
	var forged_delivery := Life.after_confirmed_delivery(hoard_3["lifecycle"],
		{"trusted_internal_apply":false,"delivery_succeeded":true,
			"ship_entity":"ecs:42"})
	_expect(errors, not bool(forged_delivery["ok"]), "untrusted_delivery_cannot_clear_hoard")
	var both := Life.default_lifecycle()
	both["hoard_strikes"] = 3
	both["broke_strikes"] = 3
	var bankruptcy_first := Life.lifecycle_step(both, ship, 2000, 1)
	_expect(errors, bankruptcy_first["commands"].size() == 1
		and bankruptcy_first["commands"][0]["reason"] == "bankruptcy",
		"bankruptcy_reason_precedes_stagnation")
	var sat := Life.default_lifecycle()
	sat["idle_ticks"] = Life.MAX_U32
	sat["hoard_strikes"] = Life.MAX_U8
	sat["broke_strikes"] = Life.MAX_U8
	var saturated := Life.lifecycle_step(sat, ship, 2500, 1)
	_expect(errors, saturated["lifecycle"]["idle_ticks"] == Life.MAX_U32
		and saturated["lifecycle"]["broke_strikes"] == Life.MAX_U8,
		"rust_u32_u8_counters_saturate_without_overflow")
	var command := at_3["commands"][0]
	var queued := Queue.stage_decommission([], command)
	_expect(errors, bool(queued["ok"]) and queued["pending"].size() == 1,
		"native_DecommissionShip_goes_to_AsyncAgentStore")
	var queued_twice := Queue.stage_decommission(queued["pending"], command)
	_expect(errors, queued_twice["pending"].size() == 2,
		"original_apply_does_not_invent_decommission_queue_dedup")
	var to_remove := Queue.drain_pending_decommissions(queued["pending"],
		{"ecs:42":{"ship_id":"ship-alpha","faction_id":"f1"}})
	_expect(errors, bool(to_remove["ok"]) and to_remove["drained"].size() == 1,
		"native_queue_requires_actual_live_identity")
	var admin_receipt := {"trusted_internal_apply":true,
		"admin_remove_succeeded":true,"ship_still_present":false,
		"ship_id":"ship-alpha"}
	var legacy := Queue.on_authoritative_ship_removed(to_remove["drained"][0],
		admin_receipt, 310, true)
	_expect(errors, bool(legacy["ok"]) and
		legacy["pending_respawn"]["spawn_at_tick"] == 620 and
		legacy["pending_respawn"]["prefer_faction"] == "f1",
		"legacy_replacement_delay_is_300_plus_tick_mod_300")
	var finite := Queue.on_authoritative_ship_removed(to_remove["drained"][0],
		admin_receipt, 310, false)
	_expect(errors, bool(finite["ok"]) and finite["pending_respawn"] == null
		and finite["events"][0]["kind"] == "fleet_loss_unreplaced",
		"genesis_finite_hulls_must_be_constructed_by_real_shipyard")
	var not_removed := admin_receipt.duplicate(true)
	not_removed["ship_still_present"] = true
	_expect(errors, not bool(Queue.on_authoritative_ship_removed(to_remove["drained"][0],
		not_removed, 310, true)["ok"]),
		"occupied_passenger_ship_cannot_be_falsely_retired_or_replaced")
	var due := Queue.due_respawns([legacy["pending_respawn"]], 620, true)
	_expect(errors, bool(due["ok"]) and due["ready"].size() == 1
		and due["pending_after"].is_empty(),
		"legacy_respawn_admission_only_after_original_delay")
	var suppressed := Queue.due_respawns([legacy["pending_respawn"]], 400, false)
	_expect(errors, bool(suppressed["ok"]) and suppressed["ready"].is_empty()
		and suppressed["events"][0]["kind"] == "free_respawn_suppressed",
		"switching_world_to_finite_hulls_discards_queued_free_respawn")
	var view_source := _wire()
	var wire := Wire.wire(view_source)
	_expect(errors, bool(wire.get("ok", false)), "native_ship_http_ws_wire_view")
	if bool(wire.get("ok", false)):
		_expect(errors, int(wire["ship"]["size_tier"]) == 3
			and wire["ship"]["size"] == "medium"
			and wire["ship"]["docked"]
			and wire["ship"]["location"] == "earth-station",
			"rust_ship_size_tier_docked_and_location")
		_expect(errors, int(wire["ship"]["crew"]["morale"]) == 50
			and int(wire["ship"]["crew"]["fatigue"]) == 78
			and int(wire["ship"]["crew"]["hunger"]) == 56,
			"rust_f32_to_u8_ui_rounding_only")
		_expect(errors, wire["ship"]["crew"]["wages_credits"] == 120
			and wire["ship"]["crew"]["current_task"] == "eating",
			"crew_morale_is_legacy_aggregate_not_new_per_crew_entities")
		_expect(errors, not wire["ship"].has("active_contract_id")
			and not wire["ship"].has("fitting")
			and not wire["ship"].has("faction_reputation"),
			"native_snapshot_optional_fields_omitted")
		_expect(errors, view_source["crew"]["morale"] == 49.6,
			"wire_does_not_round_or_mutate_persistent_crew_component")
	view_source["skills"] = null
	view_source["crew"] = null
	var legacy_crew := Wire.wire(view_source)
	_expect(errors, bool(legacy_crew["ok"])
		and int(legacy_crew["ship"]["crew"]["size"]) == 0
		and not legacy_crew["ship"]["crew"].has("skills"),
		"older_rust_snapshot_without_crew_uses_default_empty_crew")
	return {"ok": errors.is_empty(), "errors": errors}
