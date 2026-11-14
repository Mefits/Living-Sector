extends RefCounted
## N147 source-derived static scenario fixtures; intentionally NOT RUN in Godot.
## Rust: colony_development.rs migration_proposals/commission, stage-only API.
const Planner = preload("res://scripts/sim/phase1/n147_native_colony_migration_planner.gd")
const Commission = preload("res://scripts/sim/phase1/n147_native_colony_migration_commission.gd")

static func _expect(errors: Array[String], value: bool, name: String) -> void:
	if not value:
		errors.append(name)

static func _view() -> Dictionary:
	return {"faction_id": "f1", "location": "mars-colony", "phase": "migration",
		"population": 100, "missing_workers": 6, "pending_passenger_contract": null,
		"market_unambiguous": true,
		"water": 120.0, "water_reserve_target": 80.0,
		"food": 110.0, "food_reserve_target": 70.0}

static func _world() -> Dictionary:
	## 6 missing workers => ceil((6*5+2)/3) = 10 native passengers, 800 CR.
	## Nav distances represent actual N142 physical-only directed graph.
	return {"treasuries": {"f1": 10000},
		"physical_distances": {
			"earth-station": {"mars-colony": 120, "earth-station": 0},
			"shipping-lane": {"earth-station": 35},
			"mars-colony": {"mars-colony": 0}},
		"stations": [
			{"facility_type":"station", "faction_id":"f1","location":"earth-station"},
			{"facility_type":"station", "faction_id":"f1","location":"mars-colony"}],
		"households": [
			{"faction_id":"f1","location":"earth-station","population_count":80},
			{"faction_id":"f1","location":"mars-colony","population_count":100}],
		"ship_classes":{"transport":{"passenger_capacity":20},
			"scout":{"passenger_capacity":0}},
		"ships":[
			{"id":"carrier-1","faction_id":"f1","class":"transport",
				"location":"shipping-lane", "has_native_cargo":true, "fuel":10.0,
				"active_contract_id":null, "in_transit":false}],
		"contracts":[]}

static func _receipt(prepared: Dictionary) -> Dictionary:
	var post: Dictionary = prepared["post"]
	return {"trusted_internal_apply":true, "contract_id":"contract-500",
		"requestor_id":prepared["faction_id"], "faction_id":prepared["faction_id"],
		"source_location":post["source_location"],
		"destination_location":post["destination_location"],
		"quantity":post["quantity"], "initial_payment":post["payment"],
		"posted_at_tick":prepared["tick"], "mission_category":Commission.MISSION_TAG,
		"status":"posted","contract_type":"passenger",
		"funding_source":"faction","funding_reserved":prepared["escrow_reserved"],
		"faction_treasury_delta":prepared["treasury_delta"]}

static func run() -> Dictionary:
	var errors: Array[String] = []
	var w := _world()
	var original := w.duplicate(true)
	var views: Array = [_view()]
	var planned: Dictionary = Planner.plan(views, w)
	_expect(errors, bool(planned.get("ok", false)) and planned["plans"].has("f1"),
		"source_ready_colony_proposal")
	var plan: Dictionary = planned.get("plans", {}).get("f1", {})
	if plan.is_empty():
		return {"ok":false,"errors":errors}
	_expect(errors, plan["source"]=="earth-station" and plan["destination"]=="mars-colony",
		"native_directed_colony_route")
	_expect(errors, int(plan["quantity"])==10 and int(plan["payment"])==800,
		"native_10_settlers_80_cr_per_passenger")
	_expect(errors, Planner.quantity_for_missing(1)==2 and
		Planner.quantity_for_missing(12)==20 and Planner.quantity_for_missing(100)==20,
		"bounded_ceil_worker_shortfall_to_people")
	var proposal := Commission.prepare_commission(w, "f1", plan, 200, 32)
	_expect(errors, bool(proposal.get("ok", false)), "source_native_prepaid_commission")
	if bool(proposal.get("ok", false)):
		_expect(errors, int(proposal["treasury_delta"]) == -800 and
			int(proposal["escrow_reserved"]) == 800 and
			int(proposal["treasury_after"]) == 9200,
			"one_faction_cash_debit_and_one_board_escrow_reserve")
		_expect(errors, int(proposal["post"]["lifespan_ticks"]) == 25600 and
			str(proposal["post"]["mission_category"]) == "strategy.colony.workforce.v1",
			"native_800_times_multiplier_mission_tag")
		_expect(errors, str(proposal["post"]["commodity"]) == "food" and
			str(proposal["post"]["type"]) == "passenger",
			"native_food_placeholder_never_market_supply")
		_expect(errors, w == original, "pure_proposals_no_balance_or_population_mutation")
		var receipt := _receipt(proposal)
		var ack := Commission.verify_native_commission_receipt(proposal, receipt)
		_expect(errors, bool(ack.get("ok", false)) and
			ack["event"]["kind"] == "colony_workforce_contract_posted" and
			ack["event"]["contract_id"] == "contract-500",
			"exact_native_event_after_true_escrow_paid_receipt")
		receipt["funding_reserved"] = 1600
		_expect(errors, not bool(Commission.verify_native_commission_receipt(proposal, receipt).get("ok", false)),
			"falsified_paid_amount_rejected")
		receipt = _receipt(proposal)
		receipt["trusted_internal_apply"] = false
		_expect(errors, not bool(Commission.verify_native_commission_receipt(proposal, receipt).get("ok", false)),
			"untrusted_receipt_cannot_fake_contract")
	var existing := _world()
	existing["contracts"].append({"id":"another","type":"passenger","requestor_id":"f1",
		"destination_location":"mars-colony", "status":"posted","reserved_credits":0,
		"fulfiller_id":null})
	_expect(errors, Commission.prepare_commission(existing,"f1",plan,200,32)["reason"] ==
		"existing_passenger_contract", "duplicate_passenger_contract_prohibited")
	# Previously expired-but-not-refunded contract is STILL outstanding.
	existing["contracts"][0]["status"]="expired"
	existing["contracts"][0]["reserved_credits"]=800
	_expect(errors, Commission.prepare_commission(existing,"f1",plan,200,32)["reason"] ==
		"existing_passenger_contract", "expired_pending_refund_still_outstanding")
	existing["contracts"][0]["reserved_credits"]=0
	_expect(errors, bool(Commission.prepare_commission(existing,"f1",plan,200,32)["ok"]),
		"fully_refunded_expired_contract_is_not_outstanding")
	var no_carrier := _world()
	no_carrier["ships"][0]["fuel"]=0.0
	_expect(errors, not Planner.plan(views,no_carrier)["plans"].has("f1"), "no_fuel_no_migration")
	_expect(errors, Commission.prepare_commission(no_carrier,"f1",plan,200,32)["reason"] ==
		"no_idle_eligible_passenger_ship", "prepaid_commission_rechecks_fuel")
	var assigned := _world()
	assigned["contracts"].append({"id":"busy","type":"delivery",
		"requestor_id":"other","destination_location":"elsewhere",
		"status":"accepted","reserved_credits":100,"fulfiller_id":"carrier-1"})
	_expect(errors, not Planner.plan(views,assigned)["plans"].has("f1"),
		"planner_ignores_fulfiller_already_assigned_elsewhere")
	var missing_target := _world()
	missing_target["households"].pop_back()
	_expect(errors, Commission.prepare_commission(missing_target,"f1",plan,200,32)["reason"] ==
		"missing_real_source_or_destination_household",
		"no_new_ghost_colonists_when_recipient_missing")
	var settlers_floor := _world()
	settlers_floor["households"][0]["population_count"]=19
	_expect(errors, Commission.prepare_commission(settlers_floor,"f1",plan,200,32)["reason"] ==
		"missing_real_source_or_destination_household",
		"native_min_source_reserve_10_people")
	var zero_route := _world()
	zero_route["physical_distances"]["earth-station"].erase("mars-colony")
	_expect(errors, not Planner.plan(views,zero_route)["plans"].has("f1"), "physical_only_route_no_gate_teleport")
	_expect(errors, Commission.prepare_commission(zero_route,"f1",plan,200,32)["reason"] ==
		"no_physical_navigation","commission_checks_actual_registry_distance")
	var broke := _world()
	broke["treasuries"]["f1"]=5799 # 5000 reserve + 800 payment requires 5800.
	_expect(errors, not Planner.plan(views,broke)["plans"].has("f1"), "no_free_faction_escrow")
	_expect(errors, Commission.prepare_commission(broke,"f1",plan,200,32)["reason"] ==
		"below_faction_subsidy_floor", "native_floor_not_crossed")
	broke["treasuries"]["f1"]=5800
	_expect(errors, bool(Commission.prepare_commission(broke,"f1",plan,200,32)["ok"]),
		"funds_exactly_at_floor_after_paid_contract")
	var starving := _view()
	starving["food"]=0.0
	_expect(errors, not Planner.plan([starving],_world())["plans"].has("f1"),
		"life_support_before_workforce_migration")
	return {"ok": errors.is_empty(), "errors": errors}
