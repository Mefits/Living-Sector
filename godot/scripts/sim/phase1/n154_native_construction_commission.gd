extends RefCounted
## N154 — native strategy/construction.rs::run_cycle commission boundary,
## faction::ensure_site_spawned_with_material and ::refresh.
## Pure stage ONLY: never create a real ECS site, pay twice or call
## ContractBoard directly; N104 / N152 perform real escrow + posting.
const Strategy = preload("res://scripts/sim/phase1/n154_native_construction_strategy.gd")
const SITE_PROGRESS: int = 600
const LABOR_REQUIRED: int = 150
const CONSTRUCTION_BASE_PAYMENT: int = 10000
const CONSTRUCTION_LIFESPAN_BASE: int = 800
const PROJECT_TAG := "strategy.construction.v1"
const MAX_I64: int = 9223372036854775807

static func _fail(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason}

static func _site_name(location: String, target: String) -> String:
	var prefix: String = location.get_slice("-",0)
	if prefix!="":
		prefix=prefix.substr(0,1).to_upper()+prefix.substr(1)
	return prefix+" "+target.to_upper()+" Works (under construction)"

static func _position_valid(p: Variant) -> bool:
	return p is Dictionary and typeof(p.get("x")) in [TYPE_INT,TYPE_FLOAT] and \
		typeof(p.get("y")) in [TYPE_INT,TYPE_FLOAT] and \
		is_finite(float(p["x"])) and is_finite(float(p["y"]))

static func _new_site(ctx: Dictionary, faction: String, offer: Dictionary,
		tick: int, offset_position: Callable) -> Dictionary:
	var target: String = str(offer["goal"]["commodity"])
	var destination: String = str(offer["goal"]["destination"])
	var material: String = str(offer["delivery_commodity"])
	var kind: String = str(offer["facility_type"])
	# Rust ensure_site_spawned_with_material skips when any site in
	# destination has SAME ACTUAL cargo material, regardless of owner.
	for site in ctx["sites"]:
		if str(site.get("location_name",""))==destination and str(site.get("commodity",""))==material:
			return _fail("material_site_already_exists")
	var anchors := []
	for f in ctx["facilities"]:
		if str(f.get("faction_id",""))==faction and \
				str(f.get("location_name",""))==destination:
			anchors.append(f)
	anchors.sort_custom(func(a,b):return str(a["id"])<str(b["id"]))
	if anchors.is_empty() or not offset_position.is_valid():
		return _fail("missing_native_site_anchor_or_offset")
	var body: String = str(anchors[0].get("body_id",""))
	var center: Variant = ctx["body_centers"].get(body,null)
	if not _position_valid(center):
		return _fail("missing_original_body_orbit_position")
	var id: String = "site-"+target+"-"+destination+"-"+str(tick)
	var position: Variant = offset_position.call(center,id)
	if not _position_valid(position):
		return _fail("invalid_original_facility_offset")
	var site := {"id":id,"name":_site_name(destination,target),
		"facility_type":kind,"faction_id":faction,"body_id":body,
		"location_name":destination,"commodity":material,
		"progress_delivered":0,"progress_required":SITE_PROGRESS,
		"position":position,"spawned_at_tick":tick,"completed":false,"dirty":true,
		"labor":{"colony_source":null,"station_order":null,
			"required":LABOR_REQUIRED,"completed":0,"last_shift":null,
			"blocked_reason":null,"last_executor":null}}
	var event := {"kind":"construction_site_started","site_id":id,
		"name":site["name"],"facility_type":kind,"location":destination,
		"commodity":material,"target_commodity":target,"required":SITE_PROGRESS}
	return {"ok":true,"site":site,"event":event}

static func stage_commission(ctx: Dictionary, faction: Dictionary,
		offer: Dictionary, tick: int, multiplier: int,
		offset_position: Callable) -> Dictionary:
	# Input offer MUST have passed Strategy.assess_goal using same
	# snapshot, plus actual N134 authorization/Execute mode.
	if tick<0 or multiplier<0 or not bool(ctx.get("executing",false)) or \
			not bool(offer.get("ready",false)):
		return _fail("not_native_authorized_ready_construction")
	var fid: String = str(faction.get("id",""))
	var money = faction.get("treasury",null)
	if fid=="" or typeof(money)!=TYPE_INT or int(money)<Strategy.MIN_TREASURY:
		return _fail("missing_real_faction_or_treasury")
	if not bool(ctx.get("construction_authorizations",{}).get(fid,false)):
		return _fail("not_head_authorized")
	if int(money)<CONSTRUCTION_BASE_PAYMENT or \
			int(money)-Strategy.SUBSIDY_FLOOR<int(offer.get("total_cost",MAX_I64)):
		return _fail("insufficient_project_budget")
	var site: Variant = null
	var spawn: Variant = null
	if offer.get("site_id",null)==null:
		var new_site := _new_site(ctx,fid,offer,tick,offset_position)
		if not bool(new_site.get("ok",false)):
			return new_site
		site=new_site["site"]
		spawn=new_site
	else:
		for s in ctx["sites"]:
			if str(s.get("id",""))==str(offer["site_id"]) and \
					str(s.get("faction_id",""))==fid and \
					not bool(s.get("completed",false)):
				site=s.duplicate(true)
				break
		if site==null:
			return _fail("native_existing_site_missing")
	if str(site["commodity"])!=str(offer["delivery_commodity"]) or \
			str(site["location_name"])!=str(offer["goal"]["destination"]):
		return _fail("native_site_cargo_destination_mismatch")
	var from_location: String = str(offer.get("source",""))
	var dest: String = str(offer["goal"]["destination"])
	if from_location=="":
		return _fail("real_material_source_missing")
	# Original shortest_distance is in *graph hops*, not parsecs/LY.
	var distance: int = int(ctx.get("physical_distances",{}).get(from_location,{}).get(dest,0))
	if distance<0 or distance>1000000:
		return _fail("invalid_native_physical_graph_distance")
	var base_life: int = CONSTRUCTION_LIFESPAN_BASE
	if bool(ctx.get("has_director",false)):
		base_life=maxi(base_life,distance*100+1200)
	if multiplier>0 and base_life>MAX_I64/multiplier:
		return _fail("native_contract_lifespan_overflow")
	var lifespan: int = base_life*multiplier
	var qty: int = int(offer.get("quantity",0))
	if qty<=0 or qty>Strategy.DELIVERY_QUANTITY:
		return _fail("invalid_native_material_shipment")
	var post := {"contract_type":"construction","requestor_id":fid,
		"faction_id":fid,"commodity":site["commodity"],"quantity":qty,
		"source_location":from_location,"destination_location":dest,
		"payment":CONSTRUCTION_BASE_PAYMENT,"posted_at_tick":tick,
		"lifespan_ticks":lifespan,"mission_category":PROJECT_TAG}
	# Stage both ECS spawn and actual prepaid faction contract in the
	# SAME exclusive commit. No funds move until N104 succeeds.
	return {"ok":true,"site":site,"site_spawn":spawn,
		"post":post,"treasury_before":int(money),
		"treasury_after":int(money)-CONSTRUCTION_BASE_PAYMENT,
		"effects":{"faction_treasury_delta":-CONSTRUCTION_BASE_PAYMENT,
			"contract_board_reserved_delta":CONSTRUCTION_BASE_PAYMENT},
		"requires":"one_ECS_site_spawn_plus_N104_N152_post_and_real_faction_escrow_commit"}

static func refresh(view: Dictionary, sites: Array, faction: String) -> Dictionary:
	## Original strategy/construction.rs::refresh updates only physical
	## site progress. It does NOT change observed_tick, status or
	## decision reason. Never fake progress based on contract posting.
	var result := view.duplicate(true)
	for key in ["site_id","progress_delivered","progress_required",
			"labor_completed","labor_required","labor_blocked_reason"]:
		result[key]=null if key in ["site_id","labor_blocked_reason"] else 0
	var goal: Variant = result.get("selected_goal",null)
	if not (goal is Dictionary):
		return result
	var desired: String = str(result.get("delivery_commodity",goal.get("commodity","")))
	for site in sites:
		if str(site.get("faction_id",""))!=faction or \
				str(site.get("location_name",""))!=str(goal.get("destination","")) or \
				str(site.get("commodity",""))!=desired:
			continue
		var labor: Dictionary = site.get("labor",{})
		result["site_id"]=site.get("id",null)
		result["facility_type"]=site.get("facility_type",null)
		result["progress_delivered"]=int(site.get("progress_delivered",0))
		result["progress_required"]=int(site.get("progress_required",0))
		result["labor_completed"]=int(labor.get("completed",0))
		result["labor_required"]=int(labor.get("required",0))
		result["labor_blocked_reason"]=labor.get("blocked_reason",null)
		break
	return result
