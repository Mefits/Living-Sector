extends RefCounted
## N151 SOURCE-derived contract checks; NOT EXECUTED in Godot.
const Purchase = preload("res://scripts/sim/phase1/n151_native_population_purchase.gd")
const Tick = preload("res://scripts/sim/phase1/n151_native_population_tick.gd")
const Migration = preload("res://scripts/sim/phase1/n151_native_population_migration.gd")
const Colony = preload("res://scripts/sim/phase1/n151_native_colony_commission.gd")

class Offset extends RefCounted:
	func offset(center: Dictionary, _id: String) -> Dictionary:
		## Fixture only. Real native facility_offset_position is injected.
		return {"x":float(center["x"])+1.0,"y":float(center["y"])-1.0}

static func _expect(e: Array[String],yes: bool,label: String) -> void:
	if not yes:
		e.append(label)

static func _pop(id: String = "p1") -> Dictionary:
	return {"id":id,"label":"Workers","demographic":"workers",
		"facility_location":"earth","faction_id":"f1","population_count":1000,
		"employed_fraction":0.6,"total_wealth":100,"consumption":{"food":1.0,"water":0.5},
		"food_satisfaction":50,"safety_satisfaction":60,"entertainment_satisfaction":60,
		"overall_sentiment":50,"unrest":50,"migration_pressure":0.5,
		"production_commodity":"ore","production_amount":3.0}

static func _world() -> Dictionary:
	return {"populations":[_pop()],
		"markets":{"earth":{"id":"market-earth","facility_location":"earth",
			"owner_facility_id":"station","prices":{"food":6.0,"water":4.0},
			"supply":{"food":10.0,"water":10.0},"consumption_window":{}}},
		"facilities":{"station":{"id":"station","credits":1000}},
		"fired":{"p1":1},"commodity_base_prices":{"food":6.0,"water":4.0}}

static func run() -> Dictionary:
	var errors: Array[String] = []
	var original := _world()
	var before := original.duplicate(true)
	var result := Tick.tick_populations(original,5,1.0,1)
	_expect(errors,bool(result.get("ok",false)),"pop_source_tick_admitted")
	if bool(result.get("ok",false)):
		var p: Dictionary = result["world"]["populations"][0]
		var m: Dictionary = result["world"]["markets"]["earth"]
		_expect(errors,result["purchases"].size()==2
			and int(p["total_wealth"])==92 and
			int(result["world"]["facilities"]["station"]["credits"])==1008,
			"one_8_credit_wallet_debit_equals_facility_credit")
		_expect(errors,absf(float(m["supply"]["food"])-9.0)<0.0001
			and absf(float(m["supply"]["water"])-9.5)<0.0001,
			"only_physically_purchased_items_consumed")
		_expect(errors,int(p["food_satisfaction"])==52 and int(p["overall_sentiment"])==51,
			"native_0_9_inertia_after_purchase")
		_expect(errors,result["events"].size()==3 and
			result["events"][2]["kind"]=="population_production_blocked",
			"legacy_population_production_does_not_mint_goods")
		_expect(errors,original==before,"native_prepare_is_pure")
		var snapshot := Tick.pop_wire_snapshot(p)
		_expect(errors,bool(snapshot.get("ok",false))
			and not snapshot["snapshot"].has("growth_rate"),
			"PopSnapshot_original_fields_only")
	var no_money := _world()
	no_money["populations"][0]["total_wealth"]=0
	var hunger := Tick.tick_populations(no_money,5,1.0,1)
	_expect(errors,bool(hunger.get("ok",false)) and
		hunger["world"]["populations"][0]["food_satisfaction"]==45 and
		hunger["world"]["facilities"]["station"]["credits"]==1000,
		"cannot_eat_on_credit_or_create_facility_wealth")
	var emergency := _world()
	emergency["populations"][0]["food_satisfaction"]=20
	var extra := Tick.tick_populations(emergency,5,1.0,1)
	_expect(errors,bool(extra.get("ok",false)) and extra["purchases"].size()==3
		and extra["events"][1]["commodity"]=="water" and extra["events"][2]["commodity"]=="water",
		"ordinary_water_plus_emergency_water_remain_two_source_purchases")
	var offscreen := _world()
	offscreen["fired"].clear()
	var skipped := Tick.tick_populations(offscreen,5,1.0,1)
	_expect(errors,bool(skipped.get("ok",false)) and skipped["purchases"].is_empty(),
		"LOD_non_fired_population_has_no_economy_or_fake_consumption")
	var noncycle := Tick.tick_populations(_world(),3,1.0,1)
	_expect(errors,bool(noncycle.get("ok",false)) and noncycle["skipped"],
		"source_tick_returns_before_contract_sweep_on_noncycle")
	var src := _pop("a")
	src["total_wealth"]=10000
	src["migration_pressure"]=1.1
	src["overall_sentiment"]=10
	var dest := _pop("b")
	dest["facility_location"]="mars"
	dest["population_count"]=200
	dest["total_wealth"]=500
	dest["overall_sentiment"]=80
	var moved := Migration.migrate([src,dest],200)
	_expect(errors,bool(moved.get("ok",false)) and moved["moved"]==100 and
		moved["populations"][0]["population_count"]==900 and
		moved["populations"][1]["total_wealth"]==1500,
		"native_migration_one_real_transfer_conserves_wealth_and_headcount")
	var plan := {"faction_id":"f1","source":"earth","destination":"mars-colony",
		"body":{"body_id":"mars","name":"Mars"},"site_id":null,
		"quantity":10,"cost":900,"passenger":false}
	var world := {"sites":[],"bodies":{"mars":{"universe_center":{"x":10.0,"y":20.0}}},
		"treasuries":{"f1":10000},"physical_distances":{"earth":{"mars-colony":12}},
		"has_native_director":true}
	var instance := Offset.new()
	var site := Colony.commission(plan,world,200,2,Callable(instance,"offset"))
	_expect(errors,bool(site.get("ok",false)) and site["kind"]=="spawn_construction_site"
		and site["cost"]==0 and site["site"]["labor"]["colony_source"]=="earth",
		"native_colony_approved_before_any_paid_order")
	if bool(site.get("ok",false)):
		plan["site_id"]=site["site"]["id"]
		world["sites"].append(site["site"])
		var paid := Colony.commission(plan,world,250,2,Callable(instance,"offset"))
		_expect(errors,bool(paid.get("ok",false)) and paid["post"]["lifespan_ticks"]==4800
			and paid["treasury_after"]==9100 and world["treasuries"]["f1"]==10000,
			"director_distance_scales_paid_contract_without_side_effects")
	return {"ok":errors.is_empty(),"errors":errors}
