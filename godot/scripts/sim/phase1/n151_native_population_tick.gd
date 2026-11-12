extends RefCounted
## N151 — frozen agents/population.rs::tick_populations full native order.
## One staged immutable World transaction; N71/N125/N126/N127 are earlier
## SOURCE FRAGMENTS, NOT extra callbacks to run beside this module.
const Purchase = preload("res://scripts/sim/phase1/n151_native_population_purchase.gd")
const CONSUMPTION_INTERVAL_BASE: int = 5
const PRODUCTION_INTERVAL_BASE: int = 5
const CONTRACT_POST_INTERVAL_BASE: int = 25
const PASSENGER_CONTRACT_INTERVAL_BASE: int = 60
const MIGRATION_CHECK_INTERVAL_BASE: int = 200
const FOOD_SAT_DROP_ON_SHORTAGE: int = 5
const FOOD_SAT_RECOVER_ON_MET: int = 2
const EMERGENCY_WATER_THRESHOLD: int = 30
const EMERGENCY_WATER_RATE: float = 0.5
const SENTIMENT_INERTIA_BASE: float = 0.9
const MIGRATION_SENTIMENT_FLOOR: int = 30
const MIGRATION_PRESSURE_RISE: float = 0.01
const MIGRATION_PRESSURE_DECAY: float = 0.005

static func _fail(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason}

static func _validate(world: Dictionary) -> String:
	for key in ["populations","markets","facilities","fired","commodity_base_prices"]:
		if not world.has(key):
			return "missing_native_world_projection:"+key
	if not (world["populations"] is Array and world["markets"] is Dictionary and
			world["facilities"] is Dictionary and world["fired"] is Dictionary and
			world["commodity_base_prices"] is Dictionary):
		return "invalid_native_world_projection"
	for p in world["populations"]:
		if not (p is Dictionary):
			return "invalid_pop"
		for k in ["id","facility_location","population_count","food_satisfaction",
				"safety_satisfaction","entertainment_satisfaction",
				"overall_sentiment","migration_pressure","total_wealth","consumption"]:
			if not p.has(k):
				return "missing_population_field:"+k
		if not (p["id"] is String and p["facility_location"] is String and p["consumption"] is Dictionary):
			return "invalid_population_identity"
		if not (typeof(p["population_count"])==TYPE_INT and
				typeof(p["total_wealth"])==TYPE_INT):
			return "invalid_population_count_or_cash"
		if not is_finite(float(p["migration_pressure"])):
			return "invalid_population_pressure"
	return ""

static func _demand(p: Dictionary) -> Array:
	## Rust sorts Food first, Water second, then lexical commodity slug.
	## Emergency water is an *additional* demand even if already in
	## PopEconomy.consumption; do NOT collapse those two purchase attempts.
	var rows: Array = []
	var heads: int = maxi(0,int(p["population_count"]))
	for slug in p["consumption"]:
		var rate = p["consumption"][slug]
		if not (slug is String) or not (typeof(rate) in [TYPE_INT,TYPE_FLOAT]) or not is_finite(float(rate)):
			return []
		var needed: float = Purchase._f32(float(rate)*float(heads)/1000.0)
		if needed > 0.0:
			rows.append({"commodity":slug,"needed":needed})
	if int(p["food_satisfaction"]) < EMERGENCY_WATER_THRESHOLD and heads > 0:
		rows.append({"commodity":"water",
			"needed":Purchase._f32(EMERGENCY_WATER_RATE*float(heads)/1000.0)})
	rows.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		var pa: int = 0 if a["commodity"]=="food" else (1 if a["commodity"]=="water" else 2)
		var pb: int = 0 if b["commodity"]=="food" else (1 if b["commodity"]=="water" else 2)
		if pa!=pb:
			return pa<pb
		return str(a["commodity"])<str(b["commodity"]))
	return rows

static func tick_populations(world: Dictionary, tick: int, tick_scale: float,
		multiplier: int) -> Dictionary:
	## Inputs are real ECS snapshots. 'fired' contains only populations
	## whose N140 AgentLod.try_fire actually returned Some; populations
	## without LOD MUST be included with value 1 by the native adapter.
	## Market lookup uses actual single MarketIdentity.location. If two
	## markets have same location the original HashMap iteration winner
	## is undefined; caller supplies the physical ECS-selected market.
	var bad := _validate(world)
	if bad!="":
		return _fail(bad)
	if tick<0 or multiplier<=0 or not is_finite(tick_scale) or tick_scale<0.0:
		return _fail("invalid_native_clock")
	var consumption_due: bool = tick%(CONSUMPTION_INTERVAL_BASE*multiplier)==0
	var production_due: bool = tick%(PRODUCTION_INTERVAL_BASE*multiplier)==0
	# Source RETURNS before migration/contract sweep if neither due.
	if not consumption_due and not production_due:
		return {"ok":true,"world":world.duplicate(true),"events":[],
			"purchases":[],"due":{"migration":false,"food_contract":false,
				"passenger_contract":false,"sweep":false},"skipped":true}
	var next: Dictionary = world.duplicate(true)
	var events: Array[Dictionary] = []
	var purchases: Array[Dictionary] = []
	var factor: float = pow(SENTIMENT_INERTIA_BASE,maxf(tick_scale,0.01))
	for i in range(next["populations"].size()):
		var pop: Dictionary = next["populations"][i]
		var pop_id: String = str(pop["id"])
		if not next["fired"].has(pop_id):
			continue
		var skipped = next["fired"][pop_id]
		if typeof(skipped)!=TYPE_INT or int(skipped)<1:
			return _fail("invalid_native_Lod_fired")
		# Original uses LOD only as admission; DOES NOT scale rate by skipped!
		var location: String = str(pop["facility_location"])
		if not next["markets"].has(location):
			continue
		var market: Dictionary = next["markets"][location]
		if not market.has("owner_facility_id"):
			return _fail("invalid_actual_market_owner")
		var fac_id: String = str(market["owner_facility_id"])
		if not next["facilities"].has(fac_id):
			return _fail("invalid_actual_market_seller")
		var seller: Dictionary = next["facilities"][fac_id]
		var any_shortage := false
		if consumption_due:
			for wish in _demand(pop):
				var ticket := Purchase.prepare_purchase(pop,market,seller,
					str(wish["commodity"]),float(wish["needed"]),tick,
					next["commodity_base_prices"])
				var qty: float = 0.0
				var paid: int = 0
				var reason: Variant = null
				if bool(ticket.get("ok",false)):
					qty = float(ticket["quantity"])
					paid = int(ticket["payment"])
					# This is STILL ONE pure batch plan. Physical effects
					# on staged snapshots are needed so next household
					# cannot buy the SAME physical stock twice.
					pop["total_wealth"] = ticket["after"]["population_wealth"]
					pop["sentiment_dirty"] = true
					seller["credits"] = ticket["after"]["facility_credits"]
					seller["dirty"] = true
					market["supply"][wish["commodity"]] = ticket["after"]["market_supply"]
					market["history_dirty"] = true
					var flow: Dictionary = market.get("consumption_window",{})
					var window: Array = flow.get(wish["commodity"],[]).duplicate(true)
					window.append({"tick":tick,"qty":qty})
					flow[wish["commodity"]] = window
					market["consumption_window"] = flow
					purchases.append(ticket)
				else:
					reason = str(ticket.get("reason","purchase_failed"))
				if qty < float(wish["needed"]):
					any_shortage = true
				events.append({"kind":"population_purchase","tick":tick,
					"population_id":pop_id,"commodity":wish["commodity"],
					"needed":wish["needed"],"quantity":qty,
					"payment":paid,"reason":reason})
			var food_sat: int = int(pop["food_satisfaction"])
			pop["food_satisfaction"] = maxi(0,food_sat-FOOD_SAT_DROP_ON_SHORTAGE) if any_shortage else 				mini(100,food_sat+FOOD_SAT_RECOVER_ON_MET)
			var target: int = int(
				(int(pop["food_satisfaction"])*6+
				int(pop["safety_satisfaction"])*2+
				int(pop["entertainment_satisfaction"])*2)/10)
			var raw: float = float(pop["overall_sentiment"])*factor + float(target)*(1.0-factor)
			# Rust's f32::round rounds 0.5 away from zero; Godot round
			# shares this rule, final cast follows source i32.
			pop["overall_sentiment"] = int(round(raw))
			pop["unrest"] = clampi(100-int(pop["overall_sentiment"]),0,100)
			pop["sentiment_dirty"] = true
			var delta: float = MIGRATION_PRESSURE_RISE*tick_scale if 				int(pop["overall_sentiment"])<MIGRATION_SENTIMENT_FLOOR else 				-MIGRATION_PRESSURE_DECAY*tick_scale
			pop["migration_pressure"] = clampf(
				float(pop["migration_pressure"])+delta,0.0,2.0)
		if production_due and pop.get("production_commodity",null)!=null and 				float(pop.get("production_amount",0.0))>0.0:
			# Native source forbids legacy household minting of goods.
			events.append({"kind":"population_production_blocked",
				"tick":tick,"reason":"requires_native_employer",
				"location":location})
		next["markets"][location]=market
		next["facilities"][fac_id]=seller
		next["populations"][i]=pop
	# Source gates migration/contracts/sweep even if all pops were LOD
	# skipped; these EXTERNAL native owners are not invoked here twice.
	var due: Dictionary = {
		"migration":tick%(MIGRATION_CHECK_INTERVAL_BASE*multiplier)==0,
		"food_contract":tick%(25*multiplier)==0,
		"passenger_contract":tick%(60*multiplier)==0,
		"sweep":true}
	return {"ok":true,"world":next,"events":events,
		"purchases":purchases,"due":due,"skipped":false,
		"authority":"one_native_population_ecs_and_contractboard_tick",
		"next_owners":{
			"migration":"N114 source migration with real world migration transaction",
			"food_contract":"N125 source posting + N151 actual population escrow reserve",
			"passenger_contract":"frozen Rust deliberately DISABLES unfounded posting",
			"sweep":"N145 native ContractBoard renew/expire/age ONCE"}}

static func pop_wire_snapshot(pop: Dictionary) -> Dictionary:
	## Frozen PopSnapshot::build; no fake growth_rate in the wire.
	for k in ["id","label","demographic","facility_location",
			"population_count","overall_sentiment","unrest","total_wealth",
			"food_satisfaction","employed_fraction","migration_pressure"]:
		if not pop.has(k):
			return _fail("missing_native_PopSnapshot_field:"+k)
	var fields := ["id","label","demographic","facility_location",
		"population_count","overall_sentiment","unrest","total_wealth",
		"food_satisfaction","employed_fraction","migration_pressure"]
	var out := {}
	for key in fields:
		out[key] = pop[key]
	return {"ok":true,"snapshot":out}
