extends RefCounted
## N156 — frozen agents/facility/mod.rs::tick_post_contracts_with_relations
## and bundle_convoy_plans. Full native SERVICE and RECIPE INPUT demand,
## but NO real Board or facility wallet mutation here. N104+N152 own
## one physical prepaid posting, N150 owns market/controller relations.
const MAX_ACTIVE: int = 4
const QTY_BASE: int = 50
const QTY_MIN: int = 25
const QTY_MAX: int = 200
const SHORTAGE_BUCKET: int = 30
const CREW_SHORTAGE: int = 30
const RECIPE_SHORTAGE: int = 15
const RECIPE_SUPPLY_THRESHOLD: float = 100.0
const RESERVE_THRESHOLD: float = 100.0
const REPAIR_THRESHOLD: float = 0.8
const FLAT_PAYMENT_PER_UNIT: int = 40
const CONTRACT_LIFESPAN: int = 300
const MAX_I64: int = 9223372036854775807
const SERVICE_ITEMS := ["fuel","tools"]

static func _fail(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason}

static func qty_for_shortage(age: int) -> int:
	var extra: int = maxi(0,age-30)/SHORTAGE_BUCKET
	return clampi(QTY_BASE+extra*25,QTY_MIN,QTY_MAX)

static func _active_contracts(contracts: Array, requestor: String) -> int:
	var count: int = 0
	for c in contracts:
		if c is Dictionary and str(c.get("requestor_id",""))==requestor and \
				str(c.get("status","")) in ["posted","accepted","picked_up"]:
			count += 1
	return count

static func _source_for(commodity: String, destination: String, faction: String,
		quantity: int, markets: Dictionary) -> Dictionary:
	var choices: Array = []
	for loc in markets:
		if str(loc)==destination:
			continue
		var m = markets[loc]
		if not (m is Dictionary and m.get("supply") is Dictionary and \
				m.get("prices") is Dictionary and m.get("owner") is String and \
				m.get("commerce_by_faction") is Dictionary):
			return _fail("missing_authoritative_N150_market_controller")
		if not m["commerce_by_faction"].has(faction):
			return _fail("missing_N150_commerce_permission")
		if not bool(m["commerce_by_faction"][faction]):
			continue
		var available: float = float(m["supply"].get(commodity,0.0))
		if not is_finite(available) or available < 0.0:
			return _fail("invalid_native_source_stock")
		if available < float(quantity):
			continue
		var same_faction: bool = faction!="" and str(m["owner"])==faction
		choices.append({"location":loc,"available":available,"own":same_faction})
	# The original source sorts owners-first, then stock descending,
	# then lexical location. Not cheapest-source-first.
	choices.sort_custom(func(a,b):
		if a["own"]!=b["own"]:
			return bool(a["own"])
		if float(a["available"]) != float(b["available"]):
			return float(a["available"]) > float(b["available"])
		return str(a["location"]) < str(b["location"]))
	if choices.is_empty():
		return _fail("no_real_source_stock")
	return {"ok":true,"location":choices[0]["location"]}

static func _quote(commodity: String, src: String,
		credits: int, quantity: int, markets: Dictionary) -> int:
	var price: float = float(markets[src].get("prices",{}).get(commodity,0.0))
	if not is_finite(price) or price<0.0:
		return 0
	# Frozen source uses f32 for market_based and Rust f32::round;
	# exact f32 rounding must be compared in Phase2.
	var market_based: int = int(round(price*float(quantity)*1.3))
	var flat: int = quantity*FLAT_PAYMENT_PER_UNIT
	return mini(credits,maxi(flat,market_based))

static func _plan(facility: Dictionary, commodity: String,
		destination: String, age: int, markets: Dictionary) -> Dictionary:
	var quantity: int = qty_for_shortage(age)
	var src := _source_for(commodity,destination,
		str(facility.get("faction_id","")),quantity,markets)
	if not bool(src.get("ok",false)):
		return src
	var payment: int = _quote(commodity,str(src["location"]),
		int(facility["credits"]),quantity,markets)
	if payment<=0:
		return _fail("insufficient_native_contract_payment")
	return {"ok":true,"plan":{
		"requestor_id":facility["id"],
		"faction_id":facility["faction_id"] if str(facility["faction_id"])!="" else null,
		"commodity":commodity,"destination":destination,
		"source":src["location"],"payment":payment,"quantity":quantity}}

static func _inputs_for(f: Dictionary, recipes: Array) -> Array:
	var result: Array = []
	for recipe in recipes:
		if not (recipe is Dictionary) or \
				recipe.get("facility_type",null)!=f["facility_type"]:
			continue
		for commodity in recipe.get("inputs",{}):
			if not result.has(commodity):
				result.append(commodity)
	return result

static func bundle(plans: Array, facility_credits: Dictionary) -> Dictionary:
	## A shared market receives goods from one convoy for co-located
	## facilities. If no lead can pay the SUM, keep all original plans.
	var by_key: Dictionary = {}
	var order: Array = []
	for p in plans:
		if not (p is Dictionary) or typeof(p.get("payment"))!=TYPE_INT or \
				typeof(p.get("quantity"))!=TYPE_INT:
			return _fail("invalid_native_convoy_plan")
		var key: String = JSON.stringify([p["destination"],p["commodity"]])
		if not by_key.has(key):
			by_key[key]=[]
			order.append(key)
		by_key[key].append(p.duplicate(true))
	var output: Array = []
	for key in order:
		var group: Array = by_key[key]
		if group.size()<=1:
			output.append_array(group)
			continue
		var combined_quantity: int = 0
		var combined_payment: int = 0
		for p in group:
			combined_quantity = mini(QTY_MAX*2,combined_quantity+int(p["quantity"]))
			if int(p["payment"])<0 or combined_payment>MAX_I64-int(p["payment"]):
				return _fail("native_convoy_payment_overflow")
			combined_payment += int(p["payment"])
		var lead: int = -1
		var best_money: int = -1
		for i in range(group.size()):
			var wealth: int = int(facility_credits.get(group[i]["requestor_id"],0))
			# Rust max_by_key picks the LAST equal-richest eligible plan
			if wealth>=combined_payment and wealth>=best_money:
				lead=i
				best_money=wealth
		if lead<0:
			output.append_array(group)
			continue
		var chosen: Dictionary = group[lead]
		chosen["quantity"]=combined_quantity
		chosen["payment"]=combined_payment
		output.append(chosen)
	return {"ok":true,"plans":output}

static func plan_delivery_contracts(facilities: Array, markets: Dictionary,
		contracts: Array, recipes: Array, tick: int,
		multiplier: int) -> Dictionary:
	if tick<0 or multiplier<=0:
		return _fail("invalid_native_tick")
	if tick % (50*multiplier)!=0:
		return {"ok":true,"due":false,"plans":[]}
	var plans: Array = []
	var credits: Dictionary = {}
	for f in facilities:
		if not (f is Dictionary) or not (f.get("id") is String) or \
				not (f.get("location_name") is String) or \
				not (f.get("faction_id") is String) or \
				typeof(f.get("credits"))!=TYPE_INT or \
				not (f.get("reserves") is Dictionary)):
			return _fail("missing_native_facility")
		credits[f["id"]]=f["credits"]
		if bool(f.get("abandoned",false)):
			continue
		if _active_contracts(contracts,str(f["id"]))>=MAX_ACTIVE:
			continue
		var loc: String = str(f["location_name"])
		var local: Dictionary = markets.get(loc,{})
		var shortage: Dictionary = local.get("shortage_ticks",{})
		# Source gates both service and precursor attempts by >=25×40
		# facility credits; but does not decrement theoretical cash
		# between the two candidates until the physical apply loop.
		if int(f["credits"])<QTY_MIN*FLAT_PAYMENT_PER_UNIT:
			continue
		for c in SERVICE_ITEMS:
			var reserve: float = float(f["reserves"].get(c,0.0))
			if not is_finite(reserve) or reserve<0.0:
				return _fail("invalid_service_reserve")
			if reserve>=RESERVE_THRESHOLD:
				continue
			var age: int = int(shortage.get(c,0))
			var urgent: bool = c=="tools" and \
				float(f.get("condition",1.0))<REPAIR_THRESHOLD and reserve<10.0
			if not urgent and age<CREW_SHORTAGE:
				continue
			var a := _plan(f,c,loc,age,markets)
			if bool(a.get("ok",false)):
				plans.append(a["plan"])
				break
		# Recipe inputs must be a REAL local market shortage; they are
		# not bought into service reserves. Source recipes list unique
		# input commodities in ORIGINAL RECIPES order.
		var supply: Dictionary = local.get("supply",{})
		for c in _inputs_for(f,recipes):
			var available: float = float(supply.get(c,0.0))
			if available>=RECIPE_SUPPLY_THRESHOLD:
				continue
			var age: int = int(shortage.get(c,0))
			if age<RECIPE_SHORTAGE:
				continue
			var p := _plan(f,str(c),loc,age,markets)
			if bool(p.get("ok",false)):
				plans.append(p["plan"])
				break
	var combined := bundle(plans,credits)
	if not bool(combined.get("ok",false)):
		return combined
	var pending: Array = []
	var remaining: Dictionary = credits.duplicate(true)
	for p in combined["plans"]:
		# Original mutable apply skips any later contract whose payer
		# no longer has enough cash after prior posted escrow.
		var id: String = str(p["requestor_id"])
		var payment: int = int(p["payment"])
		if int(remaining.get(id,0))<payment:
			continue
		remaining[id]=int(remaining[id])-payment
		var terms := {"contract_type":"delivery",
			"requestor_id":id,"faction_id":p["faction_id"],
			"commodity":p["commodity"],"quantity":p["quantity"],
			"source_location":p["source"],
			"destination_location":p["destination"],
			"payment":payment,"posted_at_tick":tick,
			"lifespan_ticks":300*multiplier}
		pending.append({"post":terms,
			"payer_id":id,"payer_before":credits[id],
			"proposed_aggregate_wallet_after":remaining[id],
			"requires":"one_N104_N152_ContractBoard_post_plus_Facility_funding_debit"})
	return {"ok":true,"due":true,"plans":pending,
		"wallet_after_projection":remaining,
		"authority":"exclusive_N104_paid_facility_contracts_only"}
