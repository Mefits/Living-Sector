extends RefCounted
## N154 — frozen sim_server/engine/admin.rs::try_shipyard_refit /
## apply_fitting_swap / commit_shipyard_refit / admin_refit_ship /
## admin_refit_facility. Real physical paid refit from ONE exclusive
## ECS snapshot, no second ledger or independent ShipFitting catalogue.
const MAX_I64: int = 9223372036854775807
const MAX_U32: int = 4294967295

static func _fail(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason}

static func _valid_slot_module(slot: String, slug: Variant, catalogue: Dictionary) -> bool:
	if slug==null:
		return true # native admin can clear slot, shipyard cannot.
	return slug is String and catalogue.has(slug) and \
		str(catalogue[slug].get("slot",""))==slot

static func stage_ship_refit(ship: Dictionary, yard: Variant,
		slot: String, slug: Variant, via_shipyard: bool,
		module_catalogue: Dictionary, module_recipes: Dictionary,
		native_ship_fitting_rebake: Callable) -> Dictionary:
	## ship: actual {id,class,slots,credits,base_cargo,base_speed,
	##               cargo{capacity},fuel{speed_modifier},fitting{slots}},
	## yard optional actual {id,facility_type,stock,credits,docked_ships}
	## Caller MUST ensure actual ship.position.docked_at resolves
	## the same yard entity, not merely the same location slug.
	if not (ship.get("id") is String) or str(ship.get("id","")).is_empty() or \
			not (ship.get("class") is String):
		return _fail("NoShip")
	if not ship.has("base_cargo") or not ship.has("base_speed") or \
			not (ship.get("fitting") is Dictionary):
		return _fail("NoClass")
	if not _valid_slot_module(slot,slug,module_catalogue):
		return _fail("InvalidSlug")
	var fitting: Dictionary = ship["fitting"]
	if not (fitting.get("slots") is Dictionary):
		return _fail("NoShip")
	if not fitting["slots"].has(slot):
		return _fail("InvalidSlug")
	if not native_ship_fitting_rebake.is_valid():
		return _fail("native_N51_ship_fitting_rebake_required")
	var cost: int = 0
	if via_shipyard:
		if slug==null or not (slug is String) or not module_recipes.has(slug):
			return _fail("InvalidSlug")
		if ship.get("docked_at",null)==null:
			return _fail("NotDocked")
		if not (yard is Dictionary) or str(yard.get("id",""))!=str(ship["docked_at"]) or \
				str(yard.get("facility_type",""))!="shipyard":
			return _fail("NotShipyard")
		var stock: Dictionary = yard.get("module_stock",{}).get("stock",{})
		if int(stock.get(slug,0))<=0:
			return _fail("NoStock")
		cost=int(module_recipes[slug].get("cost",-1))
		if cost<0 or typeof(ship.get("credits"))!=TYPE_INT or int(ship["credits"])<cost:
			return _fail("InsufficientCredits")
		if typeof(yard.get("credits"))!=TYPE_INT:
			return _fail("missing_real_shipyard_wallet")
	# Real engine calls ShipFitting.set, which recomputes the native
	# DerivedStats and power budget. N51 is the SINGLE catalogue owner.
	var new_ship := ship.duplicate(true)
	var prev = fitting["slots"][slot]
	new_ship["fitting"]["slots"][slot]=slug
	var derived: Variant = native_ship_fitting_rebake.call(
		new_ship["fitting"]["slots"].duplicate(true))
	if not (derived is Dictionary) or not derived.has("cargo_mult") or \
			not derived.has("speed_mult") or \
			not is_finite(float(derived["cargo_mult"])) or \
			not is_finite(float(derived["speed_mult"])):
		return _fail("native_ShipFitting_rebake_failed")
	var new_cargo: float = round(float(ship["base_cargo"])*float(derived["cargo_mult"]))
	var new_speed: float = float(ship["base_speed"])*float(derived["speed_mult"])
	if not is_finite(new_cargo) or new_cargo<0.0 or new_cargo>float(MAX_U32) or \
			not is_finite(new_speed):
		return _fail("native_physical_ship_fitting_overflow")
	new_ship["fitting"]["derived"]=derived.duplicate(true)
	var cargo: Dictionary = new_ship.get("cargo",{}).duplicate(true)
	cargo["capacity"]=int(new_cargo)
	new_ship["cargo"]=cargo
	var fuel: Dictionary = new_ship.get("fuel",{}).duplicate(true)
	fuel["speed_modifier"]=new_speed
	new_ship["fuel"]=fuel
	var life: Dictionary = new_ship.get("lifecycle",{}).duplicate(true)
	life["dirty"]=true
	new_ship["lifecycle"]=life
	var new_yard: Variant = null
	if via_shipyard:
		new_yard=yard.duplicate(true)
		new_yard["module_stock"]["stock"][slug]=int(new_yard["module_stock"]["stock"][slug])-1
		new_yard["module_stock"]["dirty"]=true
		new_ship["credits"]=int(new_ship["credits"])-cost
		# Rust saturating_add cost into real FacilityOperations wallet.
		var money: int = int(new_yard["credits"])
		new_yard["credits"]=MAX_I64 if money>MAX_I64-cost else money+cost
		new_yard["dirty"]=true
	var event: Dictionary = {"kind":"ship_refitted","id":ship["id"],"slot":slot,
		"from":prev,"to":slug,
		"via":"shipyard" if via_shipyard else "admin"}
	if via_shipyard:
		event["shipyard_id"]=yard["id"]
		event["cost"]=cost
	return {"ok":true,"ship":new_ship,"yard":new_yard,"event":event,
		"ship_wallet_delta":-cost,"shipyard_wallet_delta":cost if via_shipyard else 0,
		"module_stock_delta":-1 if via_shipyard else 0,
		"requires":"one_authoritative_shipyard_stock_wallet_fitting_swap_commit"}

static func stage_facility_admin_refit(facility: Dictionary, slot: String,
		slug: Variant, facility_catalogue: Dictionary,
		native_facility_fitting_rebake: Callable) -> Dictionary:
	## Source admin_refit_facility changes no market stock/credits
	## because it is an ADMIN override, not an economic shipyard sale.
	if not (facility.get("id") is String) or not (facility.get("fitting") is Dictionary) or \
			not (facility["fitting"].get("slots") is Dictionary):
		return _fail("missing_native_facility_fitting")
	if not facility["fitting"]["slots"].has(slot) or \
			not _valid_slot_module(slot,slug,facility_catalogue):
		return _fail("InvalidSlug")
	if not native_facility_fitting_rebake.is_valid():
		return _fail("native_facility_modules_catalogue_rebake_required")
	var next := facility.duplicate(true)
	var prev = next["fitting"]["slots"][slot]
	next["fitting"]["slots"][slot]=slug
	var derived: Variant = native_facility_fitting_rebake.call(
		next["fitting"]["slots"].duplicate(true))
	if not (derived is Dictionary):
		return _fail("native_facility_fitting_rebake_failed")
	next["fitting"]["derived"]=derived.duplicate(true)
	next["fitting"]["dirty"]=true
	return {"ok":true,"facility":next,
		"event":{"kind":"facility_refitted","id":facility["id"],"slot":slot,
			"from":prev,"to":slug},
		"requires":"single_admin_facility_fitting_ECS_commit"}

static func module_stock_take_one(module_stock: Dictionary, slug: String) -> Dictionary:
	## Frozen ModuleStock::take_one returns false if absent/zero and
	## marks dirty only on an actual decrement; never underflows u32.
	var next := module_stock.duplicate(true)
	if not (next.get("stock") is Dictionary):
		return _fail("missing_native_ModuleStock")
	var current = next["stock"].get(slug,0)
	if typeof(current)!=TYPE_INT or int(current)<=0:
		return _fail("NoStock")
	next["stock"][slug]=int(current)-1
	next["dirty"]=true
	return {"ok":true,"stock":next}
