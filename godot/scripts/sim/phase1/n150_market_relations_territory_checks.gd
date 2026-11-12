extends RefCounted
## N150 source-based scenario checks for complete Phase1 macro #9.
## AUTHORED, NOT EXECUTED — requires Phase2 Godot executable/parser.
const Market = preload("res://scripts/sim/phase1/n150_native_full_market_tick.gd")
const Relations = preload("res://scripts/sim/phase1/n150_native_full_faction_relations.gd")
const Territory = preload("res://scripts/sim/phase1/n150_native_market_territory.gd")
const Crisis = preload("res://scripts/sim/phase1/n150_native_market_crisis.gd")

class PriceStub extends RefCounted:
	# N131 source formula port exists independently; this controlled
	# callable only asserts market tick cadence and dependency injection.
	func recalculate(current: float, _stock: float, _need: float,
			_elasticity: float, _shortage: int) -> float:
		return minf(500.0,current+1.0)

static func _expect(errors: Array[String], condition: bool, name: String) -> void:
	if not condition:
		errors.append(name)

static func _market() -> Dictionary:
	return {
		"id":"market-earth","facility_location":"earth-station",
		"pricing":{
			"prices":{"food":100.0},"supply":{"food":5.0},
			"demand":{"food":10.0},"price_elasticity":0.03,"spread":0.1},
		"flow":{"production":{"food":3.0},"consumption":{"food":2.0},
			"seed_demand":{},"consumption_window":{
				"food":[{"tick":5,"qty":8.0},{"tick":14,"qty":20.0}]}},
		"orders":{"pending_buys":[
				{"agent_id":"market-phantom","placed_at_tick":15},
				{"agent_id":"ship-paid","placed_at_tick":15},
				{"agent_id":"ship-old","placed_at_tick":0}],
			"pending_sells":[], "reserved":{"food":{"ship-paid":2.0}},
			"next_order_id":8,"next_reserve_id":12,"order_expiry_ticks":50},
		"history":{"trend_samples":[],"trade_volume":{"food":3.0},
			"shortage_ticks":{"food":0}, "spawned_at_tick":null,
			"last_tick":0,"dirty":false,"crisis_notified":{"food":false}}
	}

static func run() -> Dictionary:
	var errors: Array[String] = []
	var original := _market()
	var before := original.duplicate(true)
	var fake := PriceStub.new()
	var price_callable := Callable(fake,"recalculate")
	var step := Market.tick_one_market(original,16,2,price_callable)
	_expect(errors,bool(step.get("ok",false)),"native_market_first_tick_full")
	if bool(step.get("ok",false)):
		var m: Dictionary = step["market"]
		_expect(errors,absf(float(m["pricing"]["demand"]["food"])-28.0)<0.001,
			"first_tick_seed_demand_merged_with_observed_consumption")
		_expect(errors,absf(float(m["pricing"]["prices"]["food"])-101.0)<0.001
			and int(m["history"]["shortage_ticks"]["food"])==1,
			"native_reprice_and_shortage_normalized_speed")
		_expect(errors,m["history"]["trend_samples"].size()==1
			and m["history"]["trend_samples"][0]["tick"]==16,
			"trend_sample_every_16_raw_ticks_not_scaled_multiplier")
		_expect(errors,m["orders"]["pending_buys"].size()==2
			and m["orders"]["pending_buys"][0]["agent_id"]=="ship-paid",
			"reject_market_phantom_orders_preserve_real_payers")
		_expect(errors,m["orders"]["reserved"]==before["orders"]["reserved"]
			and m["pricing"]["supply"]==before["pricing"]["supply"]
			and m["flow"]["production"]==before["flow"]["production"],
			"no_phantom_production_or_unreserved_inventory")
		_expect(errors,m["history"]["dirty"] and original==before,
			"pure_market_stage_without_mutating_real_ECS")
		var intermediate := Market.tick_one_market(m,17,2,price_callable)
		_expect(errors,bool(intermediate.get("ok",false))
			and absf(float(intermediate["market"]["pricing"]["prices"]["food"])-101.0)<0.001
			and intermediate["market"]["history"]["trend_samples"].size()==1,
			"pricing_skipped_on_non_game_second_and_no_trend")
		var history_full := m.duplicate(true)
		var samples: Array = []
		for i in range(200):
			samples.append({"tick":i, "prices":{"food":float(i)},
				"supply":{"food":5.0}})
		history_full["history"]["trend_samples"]=samples
		var ring := Market.tick_one_market(history_full,32,2,price_callable)
		_expect(errors,bool(ring.get("ok",false))
			and ring["market"]["history"]["trend_samples"].size()==200
			and ring["market"]["history"]["trend_samples"][-1]["tick"]==32,
			"native_trend_history_bounded_200_entries")
		var wire := Market.wire_snapshot(m)
		_expect(errors,bool(wire.get("ok",false))
			and wire["snapshot"]["facility_location"]=="earth-station"
			and wire["snapshot"]["trend_samples"].size()==1
			and not wire["snapshot"].has("trade_volume"),
			"actual_native_marketSnapshot_shape")
	var recorded := Market.record_consumption(before["flow"],"food",3.0,90)
	_expect(errors,bool(recorded.get("ok",false))
		and recorded["flow"]["consumption_window"]["food"].size()==3
		and before["flow"]["consumption_window"]["food"].size()==2,
		"consumption_window_addition_only_for_real_external_consumption")
	var no_price := Market.tick_one_market(original,16,1,Callable())
	_expect(errors,not bool(no_price["ok"]), "missing_N131_price_engine_cannot_invent_price")
	var pair := Relations.set_state({},"alpha","beta",55,"neutral",0)
	_expect(errors,bool(pair.get("ok",false)),"original_relation_admin_set")
	var relations: Dictionary = pair.get("pairs",{})
	_expect(errors,Relations.state(relations,"beta","alpha")["standing"]==55
		and Relations.state(relations,"alpha","alpha")["standing"]==0,
		"canonical_symmetric_pair_and_self_noop")
	_expect(errors,Relations.pass_due(600,1) and
		not Relations.pass_due(601,1) and Relations.pass_due(200,0),
		"server_external_200_times_multiplier_treaty_cadence")
	var alliance := Relations.tick_relations(relations,600,1)
	_expect(errors,bool(alliance.get("ok",false))
		and alliance["treaty_changes"].size()==1
		and alliance["treaty_changes"][0]["to"]=="trade_pact"
		and int(alliance["pairs"].values()[0]["last_event_tick"])==0,
		"neutral_after_sustained_500_becomes_pact_without_refreshing_last_event")
	var active := Relations.set_state(alliance["pairs"],"alpha","beta",80,"trade_pact",600)
	var ally := Relations.tick_relations(active["pairs"],1600,1)
	_expect(errors,bool(ally.get("ok",false))
		and ally["treaty_changes"].size()==1
		and ally["treaty_changes"][0]["to"]=="allied",
		"pact_after_sustained_1000_becomes_allied")
	_expect(errors,Relations.trade_pact_payment_multiplier(ally["pairs"],"alpha","beta")==1.15
		and Relations.trade_pact_dock_modifier(ally["pairs"],"alpha","beta")["fee_factor"]==0.6
		and Relations.treaty_rep_floors(ally["pairs"],"alpha")["beta"]==70,
		"allied_reputation_contract_and_dock_benefits")
	var crashed := Relations.set_state(ally["pairs"],"alpha","beta",-75,"allied",1800)
	var hostile := Relations.tick_relations(crashed["pairs"],2000,1)
	_expect(errors,hostile["treaty_changes"][0]["to"]=="hostile"
		and not Relations.commerce_allowed(hostile["pairs"],"alpha","beta")
		and Relations.market_buy_multiplier(hostile["pairs"],"alpha",0,"beta")>1.25,
		"deep_negative_hostile_commerce_block_and_price_surcharge")
	var explicit_war := Relations.set_treaty(hostile["pairs"],"alpha","beta","war",2100)
	var war := Relations.tick_relations(explicit_war["pairs"],2400,1)
	_expect(errors,bool(war.get("ok",false))
		and war["treaty_changes"].is_empty()
		and Relations.state(war["pairs"],"beta","alpha")["treaty"]=="war",
		"war_is_manual_only_and_sticky_even_after_decay")
	var decays := Relations.set_state({},"earth","mars",30,"neutral",0)
	var early := Relations.tick_relations(decays["pairs"],1999,1)
	var late := Relations.tick_relations(decays["pairs"],2000,1)
	_expect(errors,early["pairs"].values()[0]["standing"]==30
		and late["pairs"].values()[0]["standing"]==29,
		"standing_decay_only_after_exact_2000_freshness_grace")
	_expect(errors,Relations.market_sell_multiplier({}, "trader",50,"unowned")
		==1.0 and Relations.own_market_priority("earth","earth")==1.25,
		"neutral_trade_and_same_faction_preference")
	var locations := [
		{"location":"port","faction_id":"alpha","facility_type":"station"},
		{"location":"port","faction_id":"beta","facility_type":"gate"},
		{"location":"port","faction_id":"beta","facility_type":"gate"}]
	var controllers := Relations.market_controllers(locations)
	_expect(errors,controllers.get("port","")=="beta",
		"market_controller_location_counts_gates_as_real_facilities")
	var body := Territory.derive([
		{"body_id":"earth","system_name":"sol"},
		{"body_id":"mars","system_name":"sol"},
		{"body_id":"venus","system_name":"sol"}],[
		{"body_id":"earth","faction_id":"alpha","facility_type":"station","credits":100},
		{"body_id":"earth","faction_id":"beta","facility_type":"gate","credits":99999},
		{"body_id":"mars","faction_id":"beta","facility_type":"station","credits":90},
		{"body_id":"mars","faction_id":"alpha","facility_type":"station","credits":150}])
	_expect(errors,bool(body.get("ok",false))
		and body["bodies"]["earth"]["controlling_faction"]=="alpha"
		and body["bodies"]["mars"]["controlling_faction"]=="alpha"
		and body["bodies"]["mars"]["contested"]
		and body["bodies"]["venus"]["controlling_faction"]==null
		and body["systems"]["sol"]=="alpha",
		"body_gates_excluded_credit_tie_break_and_unsettled_system_rollup")
	var tied := Territory.derive([
		{"body_id":"earth","system_name":"sol"},
		{"body_id":"mars","system_name":"sol"}],[
		{"body_id":"earth","faction_id":"alpha","facility_type":"station","credits":100},
		{"body_id":"mars","faction_id":"beta","facility_type":"station","credits":100}])
	_expect(errors,bool(tied["ok"]) and tied["systems"]["sol"]==null,
		"system_control_genuine_1_to_1_tie_yields_none")
	var crisis_market := _market()
	crisis_market["history"]["shortage_ticks"]["food"]=200
	var scan := Crisis.scan({"market-earth":crisis_market},200,50)
	_expect(errors,bool(scan.get("ok",false)) and scan["events"].size()==1
		and scan["events"][0]["kind"]=="market_crisis",
		"market_shortage_crisis_hysteresis_fires_once")
	var scan2 := Crisis.scan(scan["markets"],200,50)
	_expect(errors,bool(scan2.get("ok",false)) and scan2["events"].is_empty(),
		"market_crisis_no_repeated_warning_when_still_short")
	scan2["markets"]["market-earth"]["history"]["shortage_ticks"]["food"]=50
	var recovered := Crisis.scan(scan2["markets"],200,50)
	_expect(errors,bool(recovered.get("ok",false)) and recovered["events"].size()==1
		and recovered["events"][0]["kind"]=="market_recovered",
		"market_recovery_at_inclusive_threshold_clears_crisis_flag")
	return {"ok": errors.is_empty(), "errors": errors}
