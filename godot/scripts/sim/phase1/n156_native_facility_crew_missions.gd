extends RefCounted
## N156: frozen economy/missions.rs + facility/mod.rs::tick_post_crew_missions.
## Exactly nine source missions. HashMap DefaultHasher (String+tick) is
## delegated to an injected original-Rust hash_flip callback; replacing
## it with Godot hash() or random() would destroy Rust repeatability.
## This module only produces prepaid requests; N104/N152 sole money/Board.
const INTERVAL: int = 100
const MAX_ACTIVE: int = 1
const CHANCE: float = 0.25
const LIFESPAN: int = 200

const CATALOG := [
	{"category":"security_detail","posted_by":["station"],"duration_ticks":30,
		"base_payment":1500,"required_skill":"combat","skill_gain":3},
	{"category":"vip_escort","posted_by":["station"],"duration_ticks":20,
		"base_payment":1200,"required_skill":"navigation","skill_gain":2},
	{"category":"customs_assist","posted_by":["station"],"duration_ticks":15,
		"base_payment":800,"required_skill":"trading","skill_gain":2},
	{"category":"heavy_maintenance","posted_by":["mining_rig","refinery"],"duration_ticks":40,
		"base_payment":2000,"required_skill":"engineering","skill_gain":3},
	{"category":"salvage_operation","posted_by":["mining_rig"],"duration_ticks":35,
		"base_payment":1800,"required_skill":"engineering","skill_gain":2},
	{"category":"production_assist","posted_by":["factory"],"duration_ticks":25,
		"base_payment":1400,"required_skill":"engineering","skill_gain":2},
	{"category":"equipment_calibration","posted_by":["factory","refinery"],"duration_ticks":20,
		"base_payment":1100,"required_skill":"engineering","skill_gain":2},
	{"category":"harvest_help","posted_by":["farm"],"duration_ticks":30,
		"base_payment":1200,"required_skill":"navigation","skill_gain":1},
	{"category":"safety_audit","posted_by":["refinery"],"duration_ticks":25,
		"base_payment":1500,"required_skill":"engineering","skill_gain":2}
]

static func _fail(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason}

static func source_catalogue_for(facility_type: String) -> Array:
	var out: Array = []
	for m in CATALOG:
		if m["posted_by"].has(facility_type):
			out.append(m.duplicate(true))
	return out

static func mission_by_category(category: String) -> Dictionary:
	for m in CATALOG:
		if m["category"]==category:
			return m.duplicate(true)
	return {}

static func plan_missions(facilities: Array, contracts: Array,
		tick: int, multiplier: int, rust_hash_flip: Callable) -> Dictionary:
	if tick<0 or multiplier<=0:
		return _fail("invalid_native_crew_mission_clock")
	if tick % (INTERVAL*multiplier) != 0:
		return {"ok":true,"due":false,"posts":[]}
	if not rust_hash_flip.is_valid():
		return _fail("missing_real_Rust_DefaultHasher_probability")
	var result: Array = []
	var wallet_after := {}
	for f in facilities:
		if not (f is Dictionary) or not (f.get("id") is String) or \
				not (f.get("facility_type") is String) or \
				not (f.get("location_name") is String) or \
				typeof(f.get("credits"))!=TYPE_INT or \
				not (f.get("faction_id") is String)):
			return _fail("invalid_real_mission_facility")
		if bool(f.get("abandoned",false)):
			continue
		var templates := source_catalogue_for(str(f["facility_type"]))
		if templates.is_empty():
			continue
		var active: int = 0
		for contract in contracts:
			if not (contract is Dictionary):
				return _fail("invalid_native_ContractBoard_snapshot")
			if str(contract.get("requestor_id",""))==str(f["id"]) and \
					str(contract.get("contract_type",""))=="crew_mission" and \
					str(contract.get("status","")) in ["posted","accepted","picked_up"]:
				active+=1
		if active>=MAX_ACTIVE:
			continue
		# Source DefaultHasher hashes facility_id THEN raw u64 tick, then
		# roll=(finish()%1000)/1000. Native adapter must return true for
		# that exact threshold, not an invented GDScript hash.
		var eligible: Variant = rust_hash_flip.call(f["id"],tick,CHANCE)
		if not (eligible is bool):
			return _fail("invalid_source_native_hash_roll")
		if not eligible:
			continue
		var template: Dictionary = templates[tick%templates.size()]
		var payment: int = int(template["base_payment"])
		if int(f["credits"])<payment:
			continue
		# Source Board.post_crew_mission sets commodity=Tools via
		# N152 and quantity=duration base ticks; no fabricated Tools
		# are removed when the mission is posted.
		var terms := {"contract_type":"crew_mission",
			"requestor_id":f["id"],
			"faction_id":null if str(f["faction_id"]).is_empty() else f["faction_id"],
			"commodity":"tools",
			"quantity":int(template["duration_ticks"]),
			"source_location":f["location_name"],
			"destination_location":f["location_name"],
			"payment":payment,"posted_at_tick":tick,
			"lifespan_ticks":LIFESPAN*multiplier,
			"mission_category":template["category"]}
		result.append({"post":terms,"payer_id":f["id"],
			"category":template["category"],"skill":template["required_skill"],
			"skill_gain":int(template["skill_gain"]),
			"funding_source":"facility","requires":
				"one_real_N104_prepaid_facility_escrow_and_N152_ContractBoard_post"})
		wallet_after[str(f["id"])]=int(f["credits"])-payment
	return {"ok":true,"due":true,"posts":result,
		"wallet_after_projection":wallet_after,
		"authority":"exclusive_N104_N152_real_paid_mission_apply"}
