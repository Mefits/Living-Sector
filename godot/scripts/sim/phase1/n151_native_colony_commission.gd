extends RefCounted
## N151 — frozen strategy/colony.rs::commission corrected full source
## behavior. N118 is a partial reference; this is the Phase1 *single*
## authoritative proposed site/contract transaction. NO direct spawns,
## money, citizen transport or free ships performed here.
const SETTLERS: int = 10
const CONSTRUCTION_PROGRESS_REQUIRED: int = 600
const SUBSIDY_FLOOR: int = 5000
const CONSTRUCTION_LIFESPAN_BASE: int = 800
const PROJECT_TAG: String = "strategy.colony.v1"

static func _fail(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason}

static func _valid_position(p: Variant) -> bool:
	return p is Dictionary and typeof(p.get("x")) in [TYPE_INT,TYPE_FLOAT] and 		typeof(p.get("y")) in [TYPE_INT,TYPE_FLOAT] and 		is_finite(float(p["x"])) and is_finite(float(p["y"]))

static func commission(plan: Dictionary, world: Dictionary,
		tick: int, mult: int, facility_offset_position: Callable) -> Dictionary:
	## plan: real N144 Plan including src/dest, body {id,name,db_id},
	## site_id null|string, quantity, cost, passenger.
	## world: actual site ECS, body orbit universe centers, Treasury and
	## N142 physical directed shortest_distance, has_native_director.
	if tick<0 or mult<0 or not (plan.get("faction_id") is String):
		return _fail("invalid_colony_tick_or_faction")
	var faction: String = str(plan["faction_id"])
	var source: String = str(plan.get("source",""))
	var destination: String = str(plan.get("destination",""))
	var body = plan.get("body",null)
	if faction.is_empty() or source.is_empty() or destination.is_empty() or 			not (body is Dictionary) or not (body.get("body_id") is String) or 			not (body.get("name") is String):
		return _fail("invalid_colony_plan")
	if not (world.get("sites") is Array and world.get("bodies") is Dictionary and
			world.get("treasuries") is Dictionary and
			world.get("physical_distances") is Dictionary and
			typeof(world.get("has_native_director"))==TYPE_BOOL):
		return _fail("missing_native_colony_ECS")
	var site_id = plan.get("site_id",null)
	if site_id==null or site_id=="":
		# Native commission checks no ConstructionSite on this body
		# unfinished; the offset is computed by ORIGINAL facility module
		# with universe center and hashed new ID, not object coordinates.
		for site in world["sites"]:
			if site is Dictionary and str(site.get("body_id",""))==str(body["body_id"]) and 					not bool(site.get("completed",false)):
				return _fail("existing_unfinished_colony_site")
		var native_bodies: Dictionary = world["bodies"]
		if not native_bodies.has(body["body_id"]):
			return _fail("missing_native_body_orbit")
		var b: Dictionary = native_bodies[body["body_id"]]
		if not _valid_position(b.get("universe_center",null)) or 				not facility_offset_position.is_valid():
			return _fail("missing_native_facility_offset")
		var id: String = "site-station-"+destination+"-"+str(tick)
		var position: Variant = facility_offset_position.call(b["universe_center"],id)
		if not _valid_position(position):
			return _fail("invalid_native_facility_offset")
		return {"ok":true, "kind":"spawn_construction_site",
			"requires":"exclusive_native_ECS_site_spawn",
			"cost":0,"faction_id":faction,
			"site":{"id":id,"name":str(body["name"])+" Colony",
				"facility_type":"station","faction_id":faction,
				"body_id":body["body_id"],"location_name":destination,
				"commodity":"metals","progress_delivered":0,
				"progress_required":CONSTRUCTION_PROGRESS_REQUIRED,
				"position":position,"spawned_at_tick":tick,
				"completed":false,"dirty":true,
				"labor":{"colony_source":source}},
			"event":{"kind":"colony_approved","faction_id":faction,
				"site_id":id,"tick":tick,"source":source,
				"destination":destination,"body_id":body["body_id"],
				"estimated_cost":int(plan.get("cost",0))}}
	# Native does not invent a second site or fallback to zero-priced
	# phantom ships. An already selected site must be real in world.
	if not (site_id is String) or str(site_id).is_empty():
		return _fail("invalid_active_site")
	var exists := false
	for site in world["sites"]:
		if site is Dictionary and str(site.get("id",""))==str(site_id):
			exists = true
			break
	if not exists:
		return _fail("missing_native_existing_site")
	if not (world["treasuries"].has(faction)) or 			typeof(world["treasuries"][faction])!=TYPE_INT:
		return _fail("missing_real_faction_treasury")
	var cost = plan.get("cost")
	var quantity = plan.get("quantity")
	if typeof(cost)!=TYPE_INT or int(cost)<0 or typeof(quantity)!=TYPE_INT or int(quantity)<=0:
		return _fail("invalid_paid_colony_contract")
	var money: int = int(world["treasuries"][faction])
	if money - SUBSIDY_FLOOR < int(cost):
		return _fail("insufficient_colony_subsidy_budget")
	var distances: Dictionary = world["physical_distances"]
	var dist: int = 0
	if distances.get(source) is Dictionary:
		var d: Variant = distances[source].get(destination,null)
		if typeof(d)==TYPE_INT and int(d)>=0:
			dist = int(d)
	# Frozen source uses 800 only when there is no Director; with a
	# Director: max(800,distance*100+1200), then × mult unmodified.
	var lifespan: int = CONSTRUCTION_LIFESPAN_BASE
	if bool(world["has_native_director"]):
		lifespan = maxi(lifespan, dist*100+1200)
	lifespan *= mult
	var passenger: bool = bool(plan.get("passenger",false))
	var post := {"type":"passenger" if passenger else "construction",
		"requestor_id":faction,"faction_id":faction,
		"commodity":"food" if passenger else "metals",
		"quantity":int(quantity),"source_location":source,
		"destination_location":destination,"payment":int(cost),
		"posted_at_tick":tick,"lifespan_ticks":lifespan,
		"funding_source":"faction","funding_reserved":int(cost),
		"mission_category":PROJECT_TAG}
	return {"ok":true,"kind":"post_prepaid_colony_contract",
		"requires":"single_ContractBoard_post_and_register_prepaid_Faction_plus_real_treasury_debit",
		"site_id":site_id,"faction_id":faction,
		"treasury_before":money,"treasury_after":money-int(cost),
		"post":post,"debit":int(cost),
		"effects":{"faction_treasury_delta":-int(cost),
			"reserved_board_funding_delta":int(cost)}}
