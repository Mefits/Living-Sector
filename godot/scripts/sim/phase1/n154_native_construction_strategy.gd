extends RefCounted
## N154 — frozen strategy/construction.rs native strategic construction offer.
## All state is READ-ONLY; no second head, wallet, market, site or Board.
## Source facts are explicit ECS projections supplied by the Phase2 owner.
const BASE_PAYMENT: int = 10000
const DELIVERY_QUANTITY: int = 200
const STARTUP_CAPITAL: int = 20000
const MIN_TREASURY: int = 30000
const SUBSIDY_FLOOR: int = 5000
const LABOR_REQUIRED: int = 150
const SITE_REQUIRED: int = 600
const SHORTAGE_TRIGGER: int = 600
const KINDS := {
	"ore":"mining_rig","ice":"mining_rig","gas":"mining_rig","rare_ore":"mining_rig",
	"crystal_ore":"mining_rig","metals":"refinery","water":"refinery",
	"polymers":"refinery","fuel":"refinery","alloys":"alloyplant2",
	"quantum_cores":"qfab3","components":"factory","electronics":"factory",
	"tools":"factory","luxury":"factory","medical":"factory","food":"farm"
}

static func _fail(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason}

static func _priority(commodity: String, age: int, prefer: Dictionary) -> float:
	var factor: float = clampf(float(prefer.get("secure_"+commodity,0.0)),0.0,2.0)
	return float(age)*(1.0+factor)

static func _target(site: Dictionary) -> String:
	## Source site-<target commodity>-<location>-<tick> embeds TARGET
	## while site.commodity may be different recipe feedstock.
	var id: String = str(site.get("id",""))
	if id.begins_with("site-"):
		var rest: String = id.substr(5)
		var candidate: String = rest.get_slice("-",0)
		if KINDS.has(candidate):
			return candidate
	return str(site.get("commodity",""))

static func _offer(commodity: String, destination: String, age: int,
		score: float, goal_id: String) -> Dictionary:
	return {"goal_id":goal_id,"commodity":commodity,"destination":destination,
		"shortage_ticks":age,"score":score}

static func _existing_site(sites: Array, location: String, commodity: String) -> Dictionary:
	for site in sites:
		if str(site.get("location_name",""))==location and _target(site)==commodity:
			return site
	return {}

static func _has_facility(facilities: Array, faction: String, location: String, kind: String) -> bool:
	for f in facilities:
		if str(f.get("faction_id",""))==faction and \
				str(f.get("location_name",""))==location and str(f.get("facility_type",""))==kind:
			return true
	return false

static func _faction_locations(facilities: Array,faction: String) -> Array:
	var locs := []
	for f in facilities:
		if str(f.get("faction_id",""))==faction and \
				str(f.get("facility_type",""))!="gate":
			var loc: String = str(f.get("location_name",""))
			if not locs.has(loc):
				locs.append(loc)
	return locs

static func _next_colony_commodity(facilities: Array, faction: String,
		location: String, resource: Dictionary) -> String:
	if not _has_facility(facilities,faction,location,"mining_rig"):
		for raw in ["ice","gas","ore"]:
			if float(resource.get(raw,0.0))>0.0:
				return raw
	elif not _has_facility(facilities,faction,location,"refinery"):
		return "water"
	elif not _has_facility(facilities,faction,location,"farm"):
		return "food"
	elif not _has_facility(facilities,faction,location,"factory"):
		return "electronics"
	return ""

static func _generate_goals(ctx: Dictionary, faction: Dictionary, owned_sites: Array,
		members: Array) -> Array:
	var id: String = str(faction["id"])
	var prefer: Dictionary = faction.get("prefer_goals",{})
	var markets: Dictionary = ctx["markets"]
	var facilities: Array = ctx["facilities"]
	var goals: Array = []
	# Oldest physical unfinished sites ALWAYS assessed first.
	for site in owned_sites:
		var loc: String = str(site["location_name"])
		var material: String = _target(site)
		var age: int = int(markets.get(loc,{}).get("shortage_ticks",{}).get(material,0))
		goals.append(_offer(material,loc,age,_priority(material,age,prefer),"expand_production"))
	var new_goals := []
	var market_locations := markets.keys()
	market_locations.sort()
	for loc in market_locations:
		if not members.has(loc):
			continue
		var shortage: Dictionary = markets[loc].get("shortage_ticks",{})
		for commodity in shortage:
			var age: int = int(shortage[commodity])
			if age<SHORTAGE_TRIGGER or not _existing_site(owned_sites,loc,commodity).is_empty():
				continue
			new_goals.append(_offer(commodity,loc,age,
				_priority(commodity,age,prefer),"expand_production"))
	# Native Director introduces a real-material causal colony chain,
	# not a free instant industrial facility.
	if bool(ctx.get("has_director",false)):
		for station in facilities:
			var loc: String = str(station.get("location_name",""))
			if str(station.get("faction_id",""))!=id or \
					str(station.get("facility_type",""))!="station" or \
					not loc.ends_with("-colony"):
				continue
			var raw: Dictionary = ctx.get("body_resources",{}).get(station.get("body_id",""),{})
			var next_kind: String = _next_colony_commodity(facilities,id,loc,raw)
			if next_kind=="":
				continue
			new_goals=new_goals.filter(func(g): return str(g["destination"])!=loc)
			var has_site: bool = false
			for site in owned_sites:
				if str(site["location_name"])==loc:
					has_site=true
					break
			if not has_site:
				new_goals.append(_offer(next_kind,loc,0,100.0,"develop_colony"))
		# Exact research/T2/T3 upgrade gated producers.
		var technologies: Dictionary = ctx.get("technologies",{}).get(id,{})
		for station in facilities:
			if str(station.get("faction_id",""))!=id or \
					str(station.get("facility_type",""))!="station":
				continue
			var tier: int = int(ctx.get("station_tiers",{}).get(station["id"],1))
			var item: String = ""
			var kind: String = ""
			var score: float = 0.0
			if tier>=3 and bool(technologies.get("quantumtech3",false)):
				item="quantum_cores"
				kind="qfab3"
				score=75.0
			elif tier>=2 and bool(technologies.get("alloytech2",false)):
				item="alloys"
				kind="alloyplant2"
				score=60.0
			if item=="":
				continue
			var loc: String = str(station["location_name"])
			var exists: bool = _has_facility(facilities,id,loc,kind)
			for site in owned_sites:
				if str(site.get("facility_type",""))==kind and str(site["location_name"])==loc:
					exists=true
			if not exists:
				new_goals.append(_offer(item,loc,0,score,"progression_industry"))
		# Director / charter / crisis / mandate decisions remain owned
		# by N134 and macro7; consume already-authorized goal facts.
		var mandate: Dictionary = ctx.get("authorized_industry_goals",{}).get(id,{})
		if not mandate.is_empty() and str(mandate.get("destination","")) in members:
			var already: bool = false
			for g in new_goals:
				if g["destination"]==mandate["destination"] and g["commodity"]==mandate["commodity"]:
					already=true
			if not already:
				new_goals.append(mandate.duplicate(true))
		var durable: Dictionary = ctx.get("persistent_objectives",{}).get(id,{})
		if bool(durable.get("can_reoffer",false)) and str(durable.get("destination","")) in members:
			var dkind: String = str(durable.get("facility_type",""))
			var dcommodity: String = str(durable.get("commodity",""))
			var dloc: String = str(durable.get("destination",""))
			if KINDS.get(dcommodity,"")==dkind and \
					not _has_facility(facilities,id,dloc,dkind):
				var planned: bool = false
				for site in owned_sites:
					if str(site["location_name"])==dloc and str(site["facility_type"])==dkind:
						planned=true
				for g in new_goals:
					if str(g["destination"])==dloc and str(g["commodity"])==dcommodity:
						planned=true
				if not planned:
					new_goals.append(_offer(dcommodity,dloc,0,80.0,"persistent_industry"))
	new_goals.sort_custom(func(a,b):
		if float(a["score"])!=float(b["score"]):
			return float(a["score"])>float(b["score"])
		if a["commodity"]!=b["commodity"]:
			return str(a["commodity"])<str(b["commodity"])
		return str(a["destination"])<str(b["destination"]))
	goals.append_array(new_goals)
	return goals

static func _choose_source(ctx: Dictionary, faction: String, location: String,
		commodity: String, quantity: int) -> Dictionary:
	# Frozen strategy/sourcing.rs::Sources.choose:
	# real location+owner+market, no same-location purchase, stock>=qty,
	# market_buy_multiplier at original rep0, ceil(price*qty)<10000,
	# own faction supply preferred then cheapest then location.
	# Actual multipliers are injected from N150 only; no second treaty.
	var best := {}
	var has_stock := false
	var keys: Array = ctx["markets"].keys()
	keys.sort()
	for loc in keys:
		if loc==location:
			continue
		var market: Dictionary = ctx["markets"][loc]
		if not bool(market.get("commerce_allowed",{}).get(faction,true)):
			continue
		var stock: float = float(market.get("supply",{}).get(commodity,0.0))
		if not is_finite(stock) or stock<float(quantity):
			continue
		has_stock=true
		var owner: String = str(market.get("owner",""))
		# Never invent a neutral relation/price for a populated foreign
		# market. The actual N150 source treaty/market pricing supplies
		# the ship-independent rep0 quote and commerce permission.
		if not market.get("buy_multiplier_by_faction",{}).has(faction):
			return _fail("missing_N150_native_market_buy_multiplier")
		if not market.get("commerce_allowed",{}).has(faction):
			return _fail("missing_N150_native_commerce_permission")
		var price: float = float(market.get("prices",{}).get(commodity,
			ctx.get("commodity_base_prices",{}).get(commodity,0.0)))
		var mult: float = float(market["buy_multiplier_by_faction"][faction])
		if not is_finite(price) or not is_finite(mult) or price<=0.0 or mult<=0.0:
			return _fail("invalid_real_native_market_quote")
		var quote: float = ceil(price*mult*float(quantity))
		if not is_finite(quote) or quote<=0.0 or quote>=float(BASE_PAYMENT):
			continue
		var candidate := {"source":loc,"cost":int(quote),"is_foreign":owner!=faction}
		if best.is_empty() or (best["is_foreign"] and not candidate["is_foreign"]) or \
				(best["is_foreign"]==candidate["is_foreign"] and \
					(candidate["cost"]<best["cost"] or \
					(candidate["cost"]==best["cost"] and str(loc)<str(best["source"])))):
			best=candidate
	if best.is_empty():
		return _fail("unprofitable_source" if has_stock else "no_accessible_stock")
	return {"ok":true,"source":best["source"],"cost":best["cost"]}

static func _fallback_input(ctx: Dictionary, owned_sites: Array, faction: String,
		goal: Dictionary, kind: String, amount: int) -> Dictionary:
	# Only for newly commissioned sites. Existing physical site commodity
	# MUST NEVER mutate to the fallback input on resume.
	var location: String = str(goal["destination"])
	var local: Dictionary = ctx["markets"].get(location,{})
	if local.is_empty():
		return _fail("no_local_market")
	for recipe in ctx.get("production_recipes",[]):
		if str(recipe.get("facility_type",""))!=kind or \
				not recipe.get("outputs",{}).has(goal["commodity"]):
			continue
		var enough: bool = true
		for input in recipe.get("inputs",{}):
			var stock: float = float(local.get("supply",{}).get(input,0.0))
			if not is_finite(stock) or stock<float(recipe["inputs"][input]):
				enough=false
		if not enough:
			continue
		for material in recipe.get("inputs",{}):
			var conflict: bool = false
			for site in owned_sites:
				if str(site.get("location_name",""))==location and \
						str(site.get("commodity",""))==material:
					conflict=true
			if conflict:
				continue
			var source := _choose_source(ctx,faction,location,str(material),amount)
			if bool(source.get("ok",false)):
				source["material"]=material
				return source
	return _fail("no_accessible_stock")

static func _station_full(ctx: Dictionary, faction: String, location: String) -> bool:
	for station in ctx["facilities"]:
		if str(station.get("faction_id",""))!=faction or \
				str(station.get("facility_type",""))!="station" or \
				str(station.get("location_name",""))!=location:
			continue
		var tier: int = int(ctx.get("station_tiers",{}).get(station["id"],1))
		var cap: int = 4 if tier<=1 else (5 if tier==2 else 6)
		var n: int = 0
		for f in ctx["facilities"]:
			if str(f.get("faction_id",""))==faction and \
					str(f.get("location_name",""))==location and \
					str(f.get("facility_type","")) not in ["station","gate"]:
				n+=1
		for site in ctx["sites"]:
			if str(site.get("faction_id",""))==faction and \
					str(site.get("location_name",""))==location and \
					not bool(site.get("completed",false)) and \
					str(site.get("facility_type",""))!="station":
				n+=1
		return n>=cap
	return false

static func assess_goal(ctx: Dictionary, faction: Dictionary, goal: Dictionary,
		owned_sites: Array, members: Array) -> Dictionary:
	var fid: String = str(faction["id"])
	var loc: String = str(goal["destination"])
	var commodity: String = str(goal["commodity"])
	var existing := _existing_site(owned_sites,loc,commodity)
	var kind: String = str(existing.get("facility_type",KINDS.get(commodity,"")))
	var body: String = str(existing.get("body_id",""))
	if body=="":
		var anchors := []
		for f in ctx["facilities"]:
			if str(f.get("faction_id",""))==fid and str(f.get("location_name",""))==loc:
				anchors.append(f)
		anchors.sort_custom(func(a,b):return str(a["id"])<str(b["id"]))
		if not anchors.is_empty():
			body=str(anchors[0].get("body_id",""))
	var placeable: bool = ctx.get("body_centers",{}).has(body)
	var riches: float = float(ctx.get("body_resources",{}).get(body,{}).get(commodity,0.0))
	var conflict: bool = false
	for site in ctx["sites"]:
		if str(site.get("location_name",""))==loc and str(site.get("commodity",""))==commodity and \
				str(site.get("faction_id",""))!=fid and not bool(site.get("completed",false)):
			conflict=true
	var remaining: int = maxi(0,int(existing.get("progress_required",SITE_REQUIRED))-
		int(existing.get("progress_delivered",0)))
	var qty: int = mini(remaining,DELIVERY_QUANTITY)
	var material: String = str(existing.get("commodity",
		"metals" if goal["goal_id"]=="develop_colony" else commodity))
	var source := _choose_source(ctx,fid,loc,material,qty)
	if existing.is_empty() and not bool(source.get("ok",false)) and not conflict and kind!="":
		var alternate := _fallback_input(ctx,owned_sites,fid,goal,kind,qty)
		if bool(alternate.get("ok",false)):
			material=str(alternate["material"])
			source=alternate
	var material_conflict: bool = false
	var already_planned: bool = false
	var already_built: bool = false
	if existing.is_empty():
		for site in ctx["sites"]:
			if str(site.get("location_name",""))==loc and str(site.get("commodity",""))==material:
				material_conflict=true
			if str(site.get("location_name",""))==loc and str(site.get("facility_type",""))==kind:
				already_planned=true
		already_built=_has_facility(ctx["facilities"],fid,loc,kind)
	var tech: Dictionary = ctx.get("technologies",{}).get(fid,{})
	var reason := "ready"
	if conflict:
		reason="site_owned_by_other_faction"
	elif kind=="":
		reason="no_producer"
	elif kind=="alloyplant2" and not bool(tech.get("alloytech2",false)):
		reason="research_required_alloytech2"
	elif kind=="qfab3" and not bool(tech.get("quantumtech3",false)):
		reason="research_required_quantumtech3"
	elif commodity=="rare_ore" and not (bool(tech.get("drilltech2",false)) and bool(tech.get("survey2",false))):
		reason="research_required_rare_ore"
	elif commodity=="crystal_ore" and not (bool(tech.get("drill3",false)) and bool(tech.get("survey3",false))):
		reason="research_required_crystal_ore"
	elif already_built:
		reason="producer_already_present"
	elif existing.is_empty() and _station_full(ctx,fid,loc):
		reason="no_free_station_slot"
	elif already_planned or material_conflict:
		reason="producer_already_planned"
	elif not placeable or not members.has(loc):
		reason="invalid_site_location"
	elif existing.is_empty() and kind=="mining_rig" and riches<=0.0:
		reason="no_local_resource"
	elif qty==0:
		reason="awaiting_paid_labor"
	elif not bool(source.get("ok",false)):
		reason=str(source.get("reason","no_accessible_stock"))
	elif int(faction["treasury"])<MIN_TREASURY:
		reason="insufficient_budget"
	var shipments: int = (remaining+DELIVERY_QUANTITY-1)/DELIVERY_QUANTITY
	var projected_cost: int = shipments*BASE_PAYMENT+STARTUP_CAPITAL+LABOR_REQUIRED
	if reason=="ready" and projected_cost>int(faction["treasury"])-SUBSIDY_FLOOR:
		reason="insufficient_project_budget"
	return {"goal":goal.duplicate(true),"facility_type":kind,"body_id":body,
		"site_id":existing.get("id",null),"delivery_commodity":material,
		"remaining":remaining,"quantity":qty,"total_cost":projected_cost,
		"source":source.get("source",null),"source_price":source.get("cost",null),
		"raw_richness":riches,"reason":reason,"ready":reason=="ready"}

static func evaluate_faction(ctx: Dictionary, faction: Dictionary, tick: int) -> Dictionary:
	if tick<0 or not (faction.get("id") is String) or \
			typeof(faction.get("treasury"))!=TYPE_INT:
		return _fail("invalid_real_faction")
	for key in ["markets","facilities","sites","body_centers"]:
		if not ctx.has(key):
			return _fail("missing_real_construction_world:"+key)
	var fid: String = str(faction["id"])
	var members := _faction_locations(ctx["facilities"],fid)
	var owned_sites := []
	for site in ctx["sites"]:
		if str(site.get("faction_id",""))==fid and not bool(site.get("completed",false)) and \
				site.get("labor",{}).get("colony_source",null)==null:
			owned_sites.append(site)
	owned_sites.sort_custom(func(a,b):
		if int(a.get("spawned_at_tick",0))!=int(b.get("spawned_at_tick",0)):
			return int(a.get("spawned_at_tick",0))<int(b.get("spawned_at_tick",0))
		return str(a["id"])<str(b["id"]))
	var held := []
	for c in ctx.get("contracts",[]):
		if str(c.get("requestor_id",""))==fid and \
				str(c.get("contract_type",""))=="construction" and \
				str(c.get("mission_category",""))!="strategy.colony.v1" and \
				(str(c.get("status","")) not in ["paid","expired"] or \
					int(c.get("funding",{}).get("reserved",0))>0):
			held.append(c)
	held.sort_custom(func(a,b):
		if int(a.get("posted_at_tick",0))!=int(b.get("posted_at_tick",0)):
			return int(a.get("posted_at_tick",0))<int(b.get("posted_at_tick",0))
		return str(a["id"])<str(b["id"]))
	var base_view := {"observed_tick":tick,"status":"idle","reason":"no_chronic_shortage",
		"selected_goal":null,"site_id":null,"facility_type":null,
		"progress_delivered":0,"progress_required":0,
		"labor_completed":0,"labor_required":0,"labor_blocked_reason":null,
		"contract_id":null,"delivery_status":null,"delivery_block_reason":null,
		"delivery_commodity":null,"offers":[]}
	if not held.is_empty():
		var c: Dictionary = held[0]
		base_view["status"]="waiting"
		base_view["reason"]="existing_contract"
		base_view["contract_id"]=c["id"]
		base_view["delivery_status"]=c.get("status",null)
		base_view["delivery_commodity"]=c.get("commodity",null)
		base_view["delivery_block_reason"]=c.get("funding",{}).get("station_order",{}).get("blocked_reason",null)
		var target: String = str(c.get("commodity",""))
		for site in owned_sites:
			if site.get("location_name")==c.get("destination_location") and \
					site.get("commodity")==c.get("commodity"):
				target=_target(site)
		base_view["selected_goal"]=_offer(target,str(c.get("destination_location","")),0,0.0,"expand_production")
		return {"ok":true,"view":base_view,"chosen":null}
	var goals := _generate_goals(ctx,faction,owned_sites,members)
	var chosen: Variant = null
	for goal in goals:
		var cand: Dictionary = assess_goal(ctx,faction,goal,owned_sites,members)
		base_view["offers"].append(cand.duplicate(true))
		var reason: String = str(cand["reason"])
		if reason!="ready":
			if base_view["selected_goal"]==null:
				base_view["selected_goal"]=goal
				base_view["facility_type"]=cand["facility_type"]
				base_view["status"]="blocked"
				base_view["reason"]=reason
			continue
		if not bool(ctx.get("executing",false)):
			if base_view["status"]!="proposed":
				base_view["status"]="proposed"
				base_view["reason"]="shadow_no_mutation"
				base_view["selected_goal"]=goal
				base_view["facility_type"]=cand["facility_type"]
			continue
		if not bool(ctx.get("construction_authorizations",{}).get(fid,false)):
			if base_view["status"]!="waiting":
				base_view["status"]="waiting"
				base_view["reason"]="head_priority"
				base_view["selected_goal"]=goal
			continue
		chosen=cand
		base_view["selected_goal"]=goal
		base_view["facility_type"]=cand["facility_type"]
		base_view["delivery_commodity"]=cand["delivery_commodity"]
		base_view["status"]="commissionable"
		base_view["reason"]="ready"
		break
	return {"ok":true,"view":base_view,"chosen":chosen}
