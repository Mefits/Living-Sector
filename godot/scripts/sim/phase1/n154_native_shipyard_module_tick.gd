extends RefCounted
## N154 — frozen facility/mod.rs::tick_produce_modules (15 × mult).
## N132 owns the exact ordered ten T2/T3 recipes. This component
## creates ONE understocked module PER shipyard PER tick only AFTER
## the existing N39/FacilityWorkforce::pay_shift completed a real
## paid local shift. No second workforce ledger or free module factory.
const TARGET_STOCK: int = 2
const INTERVAL_BASE: int = 15
const MAX_I64: int = 9223372036854775807
const CATALOG_ORDER := ["engine_t2","engine_t3","cargo_bay_t2","cargo_bay_t3",
	"sensors_t2","sensors_t3","reactor_t2","reactor_t3","comms_t2","comms_t3"]

static func _fail(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason}

static func module_stock_read(yard: Dictionary) -> Dictionary:
	var stock = yard.get("module_stock",null)
	return stock.duplicate(true) if stock is Dictionary else {"stock":{},"dirty":false}

static func plan_one(yard: Dictionary, market: Dictionary, recipes: Dictionary,
		tick: int, multiplier: int, price_fallbacks: Dictionary) -> Dictionary:
	if tick<0 or multiplier<0 or not (yard.get("id") is String) or \
			not (market.get("id") is String):
		return _fail("invalid_native_module_fact")
	if multiplier==0 or tick%(INTERVAL_BASE*multiplier)!=0:
		return {"ok":true,"due":false,"plan":null}
	if str(yard.get("facility_type",""))!="shipyard" or bool(yard.get("abandoned",false)):
		return {"ok":true,"due":true,"plan":null,"reason":"not_active_shipyard"}
	if str(yard.get("location_name",""))!=str(market.get("facility_location","")) or \
			not (market.get("supply") is Dictionary):
		return {"ok":true,"due":true,"plan":null,"reason":"no_actual_local_market"}
	var module_stock := module_stock_read(yard)
	var stock: Dictionary = module_stock["stock"]
	var supply: Dictionary = market["supply"]
	for slug in CATALOG_ORDER:
		if not (recipes.has(slug) and recipes[slug] is Dictionary):
			return _fail("missing_original_N132_module_recipe:"+slug)
		var r: Dictionary = recipes[slug]
		if typeof(stock.get(slug,0))!=TYPE_INT or int(stock.get(slug,0))<0:
			return _fail("invalid_native_module_stock")
		if int(stock.get(slug,0))>=TARGET_STOCK:
			continue
		var inputs: Dictionary = r.get("inputs",{})
		var available: bool = true
		var cost: float = 0.0
		for commodity in inputs:
			var qty = inputs[commodity]
			var actual = supply.get(commodity,0.0)
			if typeof(qty)!=TYPE_INT or int(qty)<=0 or \
					typeof(actual) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(actual)):
				return _fail("invalid_original_module_input")
			if float(actual)<float(qty):
				available=false
				break
			var unit = market.get("prices",{}).get(commodity,price_fallbacks.get(commodity,null))
			if typeof(unit) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(unit)):
				return _fail("missing_original_module_market_price")
			cost+=float(unit)*float(qty)
		if not available:
			continue
		var payment: float = ceil(cost)
		if not is_finite(payment) or payment<0.0 or payment>=float(MAX_I64):
			return _fail("invalid_native_module_input_payment")
		# Rust tick_produce_modules checks one module at first matching
		# recipe and then pay_shift. It does NOT skip to cheaper recipes
		# when the first candidate has unaffordable labor/input budget.
		return {"ok":true,"due":true,
			"plan":{"yard_id":yard["id"],"market_id":market["id"],
				"owner_facility_id":market.get("owner_facility_id",null),
				"location_name":yard["location_name"],"module_slug":slug,
				"inputs":inputs.duplicate(true),"stock_before":stock.get(slug,0),
				"supply_before":supply.duplicate(true),
				"input_payment":int(payment),"tick":tick,
				"requires":"native_FacilityWorkforce_pay_shift_before_material_and_ModuleStock"}}
	return {"ok":true,"due":true,"plan":null,"reason":"no_understocked_affordable_inputs"}

static func after_paid_shift(plan: Dictionary, yard: Dictionary, market: Dictionary,
		receipt: Dictionary) -> Dictionary:
	## Exclusive actual N39 workforce owner must confirm it already:
	## (a) paid all local workers; (b) transferred producer input cost
	## to real market owner if distinct; (c) reserved same-tick workers.
	## A client-provided flag is not proof. Only private engine calls it.
	if plan.is_empty() or not bool(receipt.get("trusted_internal_apply",false)) or \
			not bool(receipt.get("paid_shift_committed",false)) or \
			str(receipt.get("producer_id",""))!=str(plan.get("yard_id","")) or \
			str(receipt.get("stock_owner_id",""))!=str(plan.get("owner_facility_id","")) or \
			int(receipt.get("tick",-1))!=int(plan.get("tick",-2)):
		return _fail("real_native_workforce_shift_receipt_required")
	if str(yard.get("id",""))!=str(plan["yard_id"]) or \
			str(market.get("id",""))!=str(plan["market_id"]):
		return _fail("stale_yard_or_market_identity")
	var y := yard.duplicate(true)
	var m := market.duplicate(true)
	var module_stock := module_stock_read(y)
	var old: int = int(module_stock["stock"].get(plan["module_slug"],0))
	if old!=int(plan["stock_before"]) or old>=TARGET_STOCK:
		return _fail("module_stock_changed_since_workforce_admission")
	for commodity in plan["inputs"]:
		var before: float = float(plan["supply_before"].get(commodity,0.0))
		var now: float = float(m["supply"].get(commodity,0.0))
		if not is_equal_approx(before,now):
			return _fail("market_supply_changed_since_paid_shift")
		var qty: int = int(plan["inputs"][commodity])
		if now<float(qty):
			return _fail("module_materials_were_already_consumed")
		m["supply"][commodity]=maxf(0.0,now-float(qty))
	module_stock["stock"][plan["module_slug"]]=old+1
	module_stock["dirty"]=true
	y["module_stock"]=module_stock
	m["history_dirty"]=true
	return {"ok":true,"yard":y,"market":m,
		"effects":{"module_stock_delta":{plan["module_slug"]:1},
			"physical_market_supply_delta":plan["inputs"].duplicate(true)},
		"authority":"real_N39_paid_shift_then_one_same_tick_market_to_module_commit"}

static func plan_yards(yards: Array, markets: Dictionary, recipes: Dictionary,
		tick: int, multiplier: int, base_prices: Dictionary) -> Dictionary:
	## One candidate per actual non-abandoned shipyard; original ECS
	## query order is supplied by owner. Shared market stock must be
	## revalidated at commit for each paid receipt, to prevent double use.
	var plans: Array[Dictionary] = []
	for yard in yards:
		if not (yard is Dictionary) or not yard.has("location_name"):
			return _fail("invalid_native_yard_registry")
		var loc: String = str(yard["location_name"])
		if not markets.has(loc):
			continue
		var stage:=plan_one(yard,markets[loc],recipes,tick,multiplier,base_prices)
		if not bool(stage.get("ok",false)):
			return stage
		if stage.get("plan",null)!=null:
			plans.append(stage["plan"])
	return {"ok":true,"plans":plans,
		"requires":"ordered_paid_Workforce_shift_and_single_ECS_apply_per_yard"}
