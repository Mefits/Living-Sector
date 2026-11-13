extends RefCounted
## N154 source-derived checks: authored only; NO Godot runtime execution.
const Strategy = preload("res://scripts/sim/phase1/n154_native_construction_strategy.gd")
const Commission = preload("res://scripts/sim/phase1/n154_native_construction_commission.gd")
const Module = preload("res://scripts/sim/phase1/n154_native_shipyard_module_tick.gd")
const Refit = preload("res://scripts/sim/phase1/n154_native_paid_shipyard_refit.gd")
const Materializer = preload("res://scripts/sim/phase1/n154_native_construction_materialize.gd")

class NativeAdapters extends RefCounted:
	func offset(center: Dictionary, _id: String) -> Dictionary:
		# Fixture only: Phase2 injects real facility_offset_position.
		return {"x":float(center["x"])+1.0,"y":float(center["y"])-1.0}
	func rebake(slots: Dictionary) -> Dictionary:
		var speed: float = 1.15 if slots.get("engine")=="engine_t2" else 1.0
		return {"cargo_mult":1.0,"speed_mult":speed,"fuel_mult":1.0,
			"power_use":4,"power_cap":10}
	func facility_rebake(_slots: Dictionary) -> Dictionary:
		return {"production_mult":1.0,"batches_bonus":1}

static func _expect(errors: Array[String], value: bool, description: String) -> void:
	if not value:
		errors.append(description)

static func _ctx() -> Dictionary:
	return {"facilities":[{"id":"station-earth","faction_id":"f1",
			"facility_type":"station","body_id":"body-earth",
			"location_name":"earth","location_id":5}],
		"sites":[],"contracts":[],"body_centers":{"body-earth":{"x":10.0,"y":20.0}},
		"body_resources":{"body-earth":{"ore":1.0}},
		"station_tiers":{"station-earth":1},
		"technologies":{"f1":{}},"production_recipes":[],
		"commodity_base_prices":{"metals":10.0},
		"markets":{
			"earth":{"shortage_ticks":{"metals":700},"supply":{},
				"prices":{"metals":10.0},"owner":"f1"},
			"mars":{"shortage_ticks":{},"supply":{"metals":700.0},
				"prices":{"metals":10.0},"owner":"f1",
				"buy_multiplier_by_faction":{"f1":1.0},
				"commerce_allowed":{"f1":true}}},
		"has_director":true,"executing":true,
		"construction_authorizations":{"f1":true},
		"physical_distances":{"mars":{"earth":4}}}

static func run() -> Dictionary:
	var errors: Array[String] = []
	var f: Dictionary = {"id":"f1","treasury":80000,"prefer_goals":{}}
	var ctx := _ctx()
	var original: Dictionary = ctx.duplicate(true)
	var result := Strategy.evaluate_faction(ctx,f,100)
	_expect(errors,bool(result.get("ok",false)) and result["chosen"]!=null,
		"oldest_native_shortage_generates_a_source_backed_new_facility_offer")
	if not bool(result.get("ok",false)) or result.get("chosen")==null:
		return {"ok":false,"errors":errors}
	var chosen: Dictionary = result["chosen"]
	_expect(errors,str(chosen["reason"])=="ready" and chosen["quantity"]==200
		and chosen["source"]=="mars" and chosen["total_cost"]==50150
		and chosen["facility_type"]=="refinery",
		"600_units_3_funded_shipments_plus_20k_startup_150_labor")
	_expect(errors,ctx==original,"native_construction_shortlist_is_immutable")
	var adapters := NativeAdapters.new()
	var commissioned := Commission.stage_commission(ctx,f,chosen,100,1,
		Callable(adapters,"offset"))
	_expect(errors,bool(commissioned.get("ok",false)) and
		commissioned["site"]["id"]=="site-metals-earth-100" and
		commissioned["treasury_after"]==70000 and
		commissioned["post"]["lifespan_ticks"]==1600 and
		commissioned["post"]["mission_category"]=="strategy.construction.v1",
		"real_material_site_spawn_before_a_single_prepaid_10k_construction_contract")
	var shadow := _ctx()
	shadow["executing"]=false
	var shadow_result := Strategy.evaluate_faction(shadow,f,100)
	_expect(errors,bool(shadow_result["ok"]) and shadow_result["chosen"]==null
		and shadow_result["view"]["status"]=="proposed",
		"shadow_mode_shows_native_offer_without_creating_site_or_money")
	var head_wait := _ctx()
	head_wait["construction_authorizations"]["f1"]=false
	var waiting := Strategy.evaluate_faction(head_wait,f,100)
	_expect(errors,bool(waiting["ok"]) and waiting["chosen"]==null
		and waiting["view"]["reason"]=="head_priority",
		"strategy_head_priority_controls_ECS_commission_only")
	var poor_faction := f.duplicate(true)
	poor_faction["treasury"]=35000
	var underfunded := Strategy.evaluate_faction(_ctx(),poor_faction,100)
	_expect(errors,bool(underfunded["ok"]) and underfunded["chosen"]==null
		and underfunded["view"]["reason"]=="insufficient_project_budget",
		"native_project_total_budget_uses_three_contracts_startup_and_labor")
	var resume := _ctx()
	if bool(commissioned.get("ok",false)):
		var site: Dictionary = commissioned["site"].duplicate(true)
		site["progress_delivered"]=400
		site["spawned_at_tick"]=90
		resume["sites"].append(site)
		var resumed := Strategy.evaluate_faction(resume,f,110)
		_expect(errors,bool(resumed.get("ok",false)) and resumed["chosen"]!=null
			and resumed["chosen"]["site_id"]==site["id"] and
			resumed["chosen"]["remaining"]==200,
			"source_reuses_existing_partly_funded_site_not_duplicate_or_reset")
		var observed := Commission.refresh(result["view"],resume["sites"],"f1")
		_expect(errors,observed["observed_tick"]==100
			and observed["progress_delivered"]==400,
			"refresh_updates_physical_site_progress_without_faking_a_new_strategic_decision")
	var msites := [commissioned["site"].duplicate(true)]
	var shipped := Materializer.material_delivery(msites,{}, "earth","metals",800)
	_expect(errors,bool(shipped.get("ok",false)) and
		shipped["sites"][0]["progress_delivered"]==600
		and shipped["admitted_units"]==600,
		"real_material_delivery_is_capped_at_600_and_not_labor_completion")
	var delivered_unknown := Materializer.material_delivery([],
		{"earth":{"supply":{"metals":2.0}}},"earth","metals",20)
	_expect(errors,bool(delivered_unknown.get("ok",false)) and
		delivered_unknown["fallback_to_market"] and
		delivered_unknown["markets"]["earth"]["supply"]["metals"]==22.0,
		"native_missing_site_falls_back_to_actual_local_market")
	var recipes := {}
	for slug in Module.CATALOG_ORDER:
		recipes[slug]={"inputs":{"ore":99},"cost":100}
	recipes["engine_t2"]={"inputs":{"metals":3,"electronics":2,"tools":1},"cost":8000}
	var yard := {"id":"yard1","facility_type":"shipyard",
		"location_name":"earth","abandoned":false,
		"module_stock":{"stock":{"engine_t2":0},"dirty":false}}
	var market := {"id":"market-earth","facility_location":"earth",
		"owner_facility_id":"station-earth",
		"supply":{"metals":10.0,"electronics":10.0,"tools":10.0},
		"prices":{"metals":10.0,"electronics":50.0,"tools":100.0}}
	var module_plan := Module.plan_one(yard,market,recipes,15,1,{})
	_expect(errors,bool(module_plan.get("ok",false)) and
		module_plan["plan"]["module_slug"]=="engine_t2" and
		module_plan["plan"]["input_payment"]==230,
		"original_module_catalog_order_first_understocked_one_per_15_ticks")
	var receipt := {"trusted_internal_apply":true,"paid_shift_committed":true,
		"producer_id":"yard1","stock_owner_id":"station-earth","tick":15,
		"input_payment":230,"wages":2}
	var batch := Module.after_paid_shift(module_plan["plan"],yard,market,receipt)
	_expect(errors,bool(batch.get("ok",false)) and
		batch["yard"]["module_stock"]["stock"]["engine_t2"]==1 and
		batch["market"]["supply"]["metals"]==7.0 and
		batch["market"]["supply"]["electronics"]==8.0 and
		batch["market"]["supply"]["tools"]==9.0 and
		yard["module_stock"]["stock"]["engine_t2"]==0,
		"no_free_shipyard_module_without_one_real_paid_shift")
	var forged := receipt.duplicate(true)
	forged["trusted_internal_apply"]=false
	var rejected := Module.after_paid_shift(module_plan["plan"],yard,market,forged)
	_expect(errors,not bool(rejected.get("ok",false)),
		"ui_cannot_mint_modules_by_forging_workforce_receipt")
	var not_due := Module.plan_one(yard,market,recipes,14,1,{})
	_expect(errors,bool(not_due["ok"]) and not not_due["due"],
		"module_production_cadence_is_15_times_native_multiplier")
	var ship := {"id":"ship1","class":"freighter","credits":10000,
		"docked_at":"yard1","base_cargo":100,"base_speed":2.0,
		"fitting":{"slots":{"engine":"engine_t1"},"derived":{}},
		"cargo":{"capacity":100},"fuel":{"speed_modifier":2.0},
		"lifecycle":{"dirty":false}}
	var yard_refit := {"id":"yard1","facility_type":"shipyard",
		"module_stock":{"stock":{"engine_t2":1},"dirty":false},
		"credits":500}
	var catalogue := {"engine_t1":{"slot":"engine"},"engine_t2":{"slot":"engine"}}
	var module_recipes := {"engine_t2":{"cost":8000}}
	var fitting := Refit.stage_ship_refit(ship,yard_refit,"engine","engine_t2",
		true,catalogue,module_recipes,Callable(adapters,"rebake"))
	_expect(errors,bool(fitting.get("ok",false)) and
		fitting["ship"]["credits"]==2000 and fitting["yard"]["credits"]==8500 and
		fitting["yard"]["module_stock"]["stock"]["engine_t2"]==0 and
		absf(float(fitting["ship"]["fuel"]["speed_modifier"])-2.3)<0.0001 and
		not ship["lifecycle"]["dirty"] and
		fitting["ship"]["lifecycle"]["dirty"],
		"real_paid_shipyard_refit_moves_one_module_and_all_8000_credits_once")
	var poor_ship := ship.duplicate(true)
	poor_ship["credits"]=100
	var broke := Refit.stage_ship_refit(poor_ship,yard_refit,"engine","engine_t2",
		true,catalogue,module_recipes,Callable(adapters,"rebake"))
	_expect(errors,not bool(broke["ok"]) and broke["reason"]=="InsufficientCredits",
		"no_refit_when_real_ship_cannot_pay")
	var free_admin := Refit.stage_ship_refit(ship,null,"engine","engine_t2",
		false,catalogue,module_recipes,Callable(adapters,"rebake"))
	_expect(errors,bool(free_admin.get("ok",false)) and
		free_admin["ship"]["credits"]==10000,
		"native_explicit_admin_override_is_not_a_paid_shipyard_transaction")
	var final_site: Dictionary = commissioned["site"].duplicate(true)
	final_site["progress_delivered"]=600
	final_site["labor"]["completed"]=150
	final_site["labor"]["last_shift"]={"tick":125,"workers":[["pop1",10]],"wages":10}
	var material_world := {"facilities":[{"id":"station-earth","location_name":"earth",
		"location_id":5}], "factions":{"f1":{"treasury":25000}}}
	var finish_receipt := {"trusted_internal_apply":true,
		"labor_work_succeeded":true,"site_id":final_site["id"],"tick":125}
	var built := Materializer.materialize_after_paid_labor(final_site,material_world,
		finish_receipt,-1,0.0,{"slots":{}},{"crew_count":2},125)
	_expect(errors,bool(built.get("ok",false))
		and built["facility"]["credits"]==20000
		and built["world"]["factions"]["f1"]["treasury"]==5000
		and built["facility"]["crew"]["work_shift"]["tick"]==125,
		"actual_paid_materialization_transfers_existing_20k_startup_and_preserves_shift")
	var unfinished := final_site.duplicate(true)
	unfinished["labor"]["completed"]=149
	_expect(errors,not Materializer.ready_for_materialization(unfinished)
		and Materializer.labor_tick_due(125,1),
		"last_paid_worker_required_before_facility_exists")
	return {"ok":errors.is_empty(),"errors":errors}
