extends RefCounted
## N154 — frozen engine/apply.rs::apply_construction_delivery/
## tick_construction_labor + engine/drains.rs::materialize_facility.
## Direct physical effects are only pure proposals, owner = Phase2 ECS.
## Paid labor comes from N141 (shared real household wages). DB writes
## are owned by macro #10 and N151 colony establishment by macro #2.
const STARTUP_CAPITAL: int = 20000
const RECIPE_INTERVAL_BASE: int = 5
const MAX_U32: int = 4294967295
const MIN_I64: int = -9223372036854775807-1

static func _fail(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason}

static func material_delivery(sites: Array, markets: Dictionary, destination: String,
		commodity: String, quantity: int) -> Dictionary:
	## Native material delivery runs AFTER verified N104 ship cargo/
	## passenger contract; never performs another cargo or CR debit.
	if quantity<0 or quantity>MAX_U32 or destination.is_empty():
		return _fail("invalid_native_construction_delivery")
	var next_sites := sites.duplicate(true)
	var next_markets := markets.duplicate(true)
	for i in range(next_sites.size()):
		var site: Dictionary = next_sites[i]
		if str(site.get("location_name",""))!=destination or \
				str(site.get("commodity",""))!=commodity:
			continue
		var remaining: int = maxi(0,int(site.get("progress_required",0))-
			int(site.get("progress_delivered",0)))
		var admitted: int = mini(quantity,remaining)
		site["progress_delivered"]=int(site.get("progress_delivered",0))+admitted
		site["dirty"]=true
		var done: int = int(site["progress_delivered"])
		var required: int = int(site.get("progress_required",0))
		var fraction: float = 1.0 if required<=0 else clampf(float(done)/float(required),0.0,1.0)
		return {"ok":true,"sites":next_sites,"markets":next_markets,
			"admitted_units":admitted,"fallback_to_market":false,
			"events":[{"kind":"construction_progress","site_id":site.get("id"),
				"progress":fraction,"location":destination,
				"labor_completed":site.get("labor",{}).get("completed",0),
				"labor_required":site.get("labor",{}).get("required",0)}],
			"requires":"native_real_cargo_delivery_committed_before_this_advance"}
	# Actual engine degrades to REAL destination market when no site
	# matches; this doesn't mint cargo, its owner has already
	# physically delivered it.
	if next_markets.has(destination):
		var market: Dictionary = next_markets[destination]
		var supply: Dictionary = market.get("supply",{})
		supply[commodity]=float(supply.get(commodity,0.0))+float(quantity)
		market["supply"]=supply
	return {"ok":true,"sites":next_sites,"markets":next_markets,
		"admitted_units":0,"fallback_to_market":true,"events":[],
		"requires":"native_real_delivery_physical_market_fallback_once"}

static func _facility_id(location: String, display_name: String) -> String:
	## Rust strips "(under construction)" and slugifies letters
	## and digits; empty chunks removed. Original Unicode handling is
	## not translated here: non-ASCII names require true source adapter.
	var clean: String = display_name.replace("(under construction)","").strip_edges()
	var slug: String = ""
	var separator: bool = false
	for i in range(clean.length()):
		var ch: String = clean.substr(i,1).to_lower()
		var u: int = ch.unicode_at(0)
		var allowed: bool = (u>=97 and u<=122) or (u>=48 and u<=57)
		if allowed:
			if separator and not slug.is_empty():
				slug+="-"
			slug+=ch
			separator=false
		elif u<128:
			separator=true
		else:
			return ""
	return "facility-"+location+"-"+slug if slug!="" else ""

static func ready_for_materialization(site: Dictionary) -> bool:
	var labor: Dictionary = site.get("labor",{})
	return not bool(site.get("completed",false)) and \
		int(site.get("progress_delivered",0))>=int(site.get("progress_required",0)) and \
		int(labor.get("completed",0))>=int(labor.get("required",0))

static func materialize_after_paid_labor(site: Dictionary, world: Dictionary,
		paid_labor_receipt: Dictionary, next_negative_db_id: int,
		orbit_angle: Variant, fitting_default: Dictionary, crew_default: Dictionary,
		tick: int) -> Dictionary:
	## In true engine tick_construction_labor, original N141 labor::work
	## must succeed (including ZERO workers when labor already done).
	## This function must only be called after real world shift.
	if tick<0 or not ready_for_materialization(site):
		return _fail("native_site_not_completed_after_paid_labor")
	if not bool(paid_labor_receipt.get("trusted_internal_apply",false)) or \
			not bool(paid_labor_receipt.get("labor_work_succeeded",false)) or \
			str(paid_labor_receipt.get("site_id",""))!=str(site.get("id","")) or \
			int(paid_labor_receipt.get("tick",-1))!=tick:
		return _fail("actual_native_paid_labor_receipt_required")
	if site.get("labor",{}).get("colony_source",null)!=null:
		# Frozen colony::establish upgrades an existing dock + market
		# and is covered by macro2 N151; never create a second station.
		return {"ok":true,"kind":"delegate_original_colony_establish",
			"requires":"exclusive_N151_colony_dock_and_market_establishment"}
	if not (world.get("factions") is Dictionary and world.get("facilities") is Array):
		return _fail("missing_real_world_or_faction_treasury")
	var faction: String = str(site.get("faction_id",""))
	var account: Dictionary = world["factions"].get(faction,{})
	if not (account.get("treasury") is int):
		return _fail("missing_faction_treasury")
	var source_id: String = str(site.get("id",""))
	var loc: String = str(site.get("location_name",""))
	var name: String = str(site.get("name",""))
	var id: String = _facility_id(loc,name)
	if id.is_empty():
		return _fail("unsupported_nonascii_native_facility_slug")
	for f in world["facilities"]:
		if str(f.get("id",""))==id:
			return _fail("native_materialization_duplicate_facility_id")
	if next_negative_db_id>=0:
		return _fail("missing_negative_construction_DB_id_allocator")
	if not (site.get("position") is Dictionary):
		return _fail("missing_real_site_orbit_position")
	if fitting_default.is_empty() or crew_default.is_empty():
		return _fail("missing_real_facility_fitting_or_crew_default")
	var location_id: int = 0
	for f in world["facilities"]:
		if str(f.get("location_name",""))==loc:
			location_id=int(f.get("location_id",0))
			break
	var cash: int = clampi(int(account["treasury"]),0,STARTUP_CAPITAL)
	var name_clean: String = name.replace("(under construction)","").strip_edges()
	var fac := {"id":id,"db_id":next_negative_db_id,"name":name_clean,
		"facility_type":site["facility_type"],"faction_id":faction,
		"body_id":site["body_id"],"location_id":location_id,"location_name":loc,
		"docking_capacity":4,"services":["market"],"condition":1.0,
		"reputation":50,"credits":cash,"dirty":true,"starving_notified":false,
		"storage":{"reserves":{},"docked_ships":[],"pending_deliveries":[],"dock_queue":[]},
		"lifecycle":{"level":1,"xp":0,"abandon_counter":0,"abandoned":false,"dirty":false},
		"orbit_angle":orbit_angle,"position":site["position"].duplicate(true),
		"fitting":fitting_default.duplicate(true),"crew":crew_default.duplicate(true),
		"lod":"native_new_agent_lod"}
	# Preserve final N141 WorkShift through same economic checkpoint.
	fac["crew"]["work_shift"]=site.get("labor",{}).get("last_shift",null)
	var meta := {"agent_id":id,"source_site_id":source_id,"name":name_clean,
		"facility_type":site["facility_type"],"faction_id":faction,
		"body_id":site["body_id"],"location_id":location_id,
		"location_name":loc,"docking_capacity":4,"credits":cash,
		"reputation":50,"condition":1.0}
	var next_world := world.duplicate(true)
	next_world["factions"][faction]["treasury"]=int(account["treasury"])-cash
	next_world["factions"][faction]["dirty"]=true
	next_world["facilities"].append(fac)
	# Persistence and ECS entity despawn deliberately represented as
	# intents: macro10 emits INSERT+site DELETE in one real DB frame.
	return {"ok":true,"kind":"materialize_native_facility",
		"world":next_world,"facility":fac,"pending_materialization":meta,
		"despawn_site_id":source_id,
		"effects":{"faction_treasury_delta":-cash,
			"new_facility_working_capital":cash},
		"events":[{"kind":"construction_completed","site_id":source_id,
			"facility_id":id,"facility_type":site["facility_type"],
			"location":loc,"position":site["position"].duplicate(true)}],
		"requires":"one_paid_N141_shift_then_physical_ECS_create_site_despawn_and_DB_checkpoint"}

static func labor_tick_due(tick: int, multiplier: int) -> bool:
	## Original tick_construction_labor runs at recipe cadence
	## 5×max(mult,1), independently of material delivery events.
	return tick>=0 and tick%(RECIPE_INTERVAL_BASE*maxi(1,multiplier))==0
