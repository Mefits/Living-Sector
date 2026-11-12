extends RefCounted
## N156 source-derived scenarios, AUTHORED but not run under Godot.
const Lifecycle = preload("res://scripts/sim/phase1/n156_native_facility_lifecycle.gd")
const Supply = preload("res://scripts/sim/phase1/n156_native_facility_supply_offers.gd")
const Missions = preload("res://scripts/sim/phase1/n156_native_facility_crew_missions.gd")

class RustHashFixture extends RefCounted:
	func hash_flip(_facility_id: String, _tick: int, probability: float) -> bool:
		# Not a production hash substitute. Real Phase2 adapter must
		# reproduce Rust DefaultHasher over String + tick u64.
		return probability==0.25

static func _check(errors: Array[String], good: bool, name: String) -> void:
	if not good:
		errors.append(name)

static func _fac(id: String = "station-1", credits: int = 10000) -> Dictionary:
	return {"id":id,"location_name":"earth","facility_type":"station",
		"faction_id":"f1","operations":{"condition":0.75,"credits":credits,"dirty":false},
		"lifecycle":{"abandoned":false,"abandon_counter":0,"dirty":false},
		"storage":{"reserves":{"tools":2.0,"fuel":200.0},
			"dock_queue":["ship-good","ship-idle","ship-gone"]},
		"crew":{"work_shift":{"tick":99,
				"workers":[["pop-1",2],["pop-2",1]]},
			"morale":50.0,"hunger":50.0,"food_debt":10.0,"dirty":false},
		"has_agent_lod":false}

static func _markets() -> Dictionary:
	return {"earth":{"shortage_ticks":{"tools":60,"fuel":0},
			"supply":{"tools":1.0,"fuel":200.0},"prices":{"tools":10.0},
			"owner":"f1","commerce_by_faction":{"f1":true}},
		"mars":{"shortage_ticks":{},"supply":{"tools":1000.0,"fuel":1000.0},
			"prices":{"tools":10.0,"fuel":10.0},
			"owner":"f1","commerce_by_faction":{"f1":true}}}

static func run() -> Dictionary:
	var errors: Array[String] = []
	var due := Lifecycle.schedule(100,1)
	_check(errors,bool(due.get("ok",false)) and
		due["due"]["dock_queue"] and due["due"]["facility_crew"] and
		due["due"]["repair"] and due["due"]["abandonment"] and
		not due["due"]["shipyard_modules"] and due["due"]["crew_missions"],
		"native_independent_5_10_15_20_50_100_cadence")
	var base := _fac()
	var original := base.duplicate(true)
	var ships := {"ship-good":{"location_name":"earth","dock_attempt_start_tick":42},
		"ship-idle":{"location_name":"earth","dock_attempt_start_tick":null},
		"ship-gone":{"location_name":"mars","dock_attempt_start_tick":42}}
	var first := Lifecycle.start_tick([base],ships,
		{"pop-1":80.0,"pop-2":20.0},100,1.0,1)
	_check(errors,bool(first.get("ok",false)) and base==original,
		"native_facility_stage_cannot_mutate_true_ECS")
	if bool(first.get("ok",false)):
		var f: Dictionary = first["facilities_before_abandonment"][0]
		_check(errors,absf(float(f["operations"]["condition"])-0.7498)<0.00001 and
			f["storage"]["dock_queue"]==["ship-good"],
			"every_tick_condition_decay_and_real_ship_attempt_queue_cleanup")
		_check(errors,f["crew"]["morale"]==60.0 and f["crew"]["hunger"]==40.0 and
			f["crew"]["food_debt"]==0.0 and
			f["storage"]["reserves"]["tools"]==2.0,
			"real_Pop_food_satisfaction_not_duplicate_crew_food")
		_check(errors,first["repair_candidates"].size()==1 and
			first["repair_candidates"][0]["facility_id"]=="station-1",
			"source_repair_requires_paid_workforce_first")
		var no_wages := Lifecycle.after_real_paid_repairs_and_abandonment(
			first["facilities_before_abandonment"],{},100,1)
		_check(errors,bool(no_wages.get("ok",false)) and
			no_wages["facilities"][0]["storage"]["reserves"]["tools"]==2.0 and
			absf(float(no_wages["facilities"][0]["operations"]["condition"])-0.7498)<0.00001,
			"unpaid_repair_does_not_get_free_tools_or_condition")
		var paid := Lifecycle.after_real_paid_repairs_and_abandonment(
			first["facilities_before_abandonment"],
			{"station-1":{"paid_shift_committed":true,
				"trusted_internal_apply":true,"facility_id":"station-1","tick":100}},100,1)
		_check(errors,bool(paid.get("ok",false)) and
			paid["facilities"][0]["storage"]["reserves"]["tools"]==1.0 and
			absf(float(paid["facilities"][0]["operations"]["condition"])-0.7598)<0.00001,
			"paid_N39_shift_consumes_one_tool_and_repairs_exact_001")
	var starving := _fac()
	starving["operations"]["condition"]=0.05
	starving["operations"]["credits"]=50
	starving["storage"]["reserves"]["tools"]=0.0
	starving["lifecycle"]["abandon_counter"]=199
	var finished := Lifecycle.after_real_paid_repairs_and_abandonment([starving],{},100,1)
	_check(errors,bool(finished.get("ok",false)) and
		finished["facilities"][0]["lifecycle"]["abandoned"] and
		finished["events"].size()==1 and
		finished["events"][0]["kind"]=="facility_abandoned",
		"native_200_abandonment_checks_emit_one_shot_event")
	var after := Lifecycle.after_real_paid_repairs_and_abandonment(
		finished["facilities"],{},110,1)
	_check(errors,bool(after.get("ok",false)) and after["events"].is_empty(),
		"abandoned_facility_never_emits_event_twice")
	var recovered := starving.duplicate(true)
	recovered["storage"]["reserves"]["tools"]=2.0
	var revived := Lifecycle.after_real_paid_repairs_and_abandonment([recovered],{},100,1)
	_check(errors,bool(revived.get("ok",false)) and
		revived["facilities"][0]["lifecycle"]["abandon_counter"]==0 and
		not revived["facilities"][0]["lifecycle"]["abandoned"],
		"one_actual_service_restock_resets_dying_counter")
	var no_lod := _fac("no-lod")
	var with_lod := _fac("with-lod")
	with_lod["has_agent_lod"]=true
	var lod := Lifecycle.index_lod_fired([no_lod,with_lod],{})
	_check(errors,bool(lod.get("ok",false)) and
		lod["fired"].get("no-lod",null)==1 and
		not lod["fired"].has("with-lod"),
		"offscreen_facility_skips_N39_recipe_but_not_cheap_maintenance")
	var active_lod := Lifecycle.index_lod_fired([no_lod,with_lod],{"with-lod":4})
	_check(errors,active_lod["fired"]["with-lod"]==4,
		"LOD_cursor_is_solely_owned_by_actual_native_AgentLod")
	_check(errors,Supply.qty_for_shortage(30)==50 and
		Supply.qty_for_shortage(60)==75 and
		Supply.qty_for_shortage(240)>=200,
		"source_30_tick_buckets_and_25_to_200_delivery_qty")
	var buyer1 := {"id":"fac-1","faction_id":"f1","location_name":"earth",
		"facility_type":"station","credits":10000,"abandoned":false,
		"condition":0.9,"reserves":{"tools":0.0,"fuel":200.0}}
	var buyer2 := buyer1.duplicate(true)
	buyer2["id"]="fac-2"
	buyer2["credits"]=8000
	var bundled := Supply.plan_delivery_contracts([buyer1,buyer2],
		_markets(),[],[],50,1)
	_check(errors,bool(bundled.get("ok",false)) and
		bundled["plans"].size()==1 and
		bundled["plans"][0]["payer_id"]=="fac-1" and
		bundled["plans"][0]["post"]["quantity"]==150 and
		bundled["plans"][0]["post"]["payment"]==6000,
		"native_two_facilities_one_shared_market_convoy_paid_by_richest")
	var poorer := buyer1.duplicate(true)
	poorer["credits"]=3000
	var another := buyer2.duplicate(true)
	another["credits"]=3000
	var unbundled := Supply.plan_delivery_contracts([poorer,another],
		_markets(),[],[],50,1)
	_check(errors,bool(unbundled.get("ok",false)) and
		unbundled["plans"].size()==2 and
		unbundled["plans"][0]["post"]["payment"]==3000,
		"unaffordable_bundled_convoy_falls_back_to_two_paid_sources")
	var capped_contracts := []
	for n in range(4):
		capped_contracts.append({"requestor_id":"fac-1","status":"posted"})
	var capped := Supply.plan_delivery_contracts([buyer1],
		_markets(),capped_contracts,[],50,1)
	_check(errors,bool(capped["ok"]) and capped["plans"].is_empty(),
		"source_max_four_active_contracts_per_facility")
	var urgent := buyer1.duplicate(true)
	urgent["condition"]=0.75
	var early_markets := _markets()
	early_markets["earth"]["shortage_ticks"]["tools"]=0
	var emergency := Supply.plan_delivery_contracts([urgent],
		early_markets,[],[],50,1)
	_check(errors,bool(emergency.get("ok",false)) and
		emergency["plans"].size()==1 and
		emergency["plans"][0]["post"]["commodity"]=="tools",
		"tools_repair_urgency_bypasses_30_tick_market_shortage")
	var hash := RustHashFixture.new()
	_check(errors,Missions.CATALOG.size()==9 and
		Missions.source_catalogue_for("station").size()==3 and
		Missions.source_catalogue_for("refinery").size()==3,
		"exact_source_nine_crew_missions_and_type_catalogues")
	var mission := Missions.plan_missions(
		[buyer1],[],200,1,Callable(hash,"hash_flip"))
	_check(errors,bool(mission.get("ok",false)) and
		mission["posts"].size()==1 and
		mission["posts"][0]["post"]["mission_category"]=="customs_assist" and
		mission["posts"][0]["post"]["quantity"]==15 and
		mission["posts"][0]["post"]["payment"]==800,
		"source_tick_selector_chooses_real_indexed_customs_mission")
	var missing_hash := Missions.plan_missions([buyer1],[],200,1,Callable())
	_check(errors,not bool(missing_hash.get("ok",false)),
		"Rust_DefaultHasher_must_be_injected_not_replaced_with_random")
	return {"ok":errors.is_empty(),"errors":errors}
