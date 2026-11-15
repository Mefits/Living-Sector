extends RefCounted
## N148 — immutable native wire view from sim_core/agents/ship/snapshot.rs.
## This is the HTTP/WS ShipSnapshot::build shape, NOT the N54 save file.
## Real ECS ship/faction/cargo/crew/fitting/progression sources are required.
## N67 observer can consume this later; never fabricate unknown values.

const Lifecycle = preload("res://scripts/sim/phase1/n148_native_ship_lifecycle.gd")
const SIZE_NAMES := ["tiny", "small", "medium", "large", "huge", "massive"]
const CREW_TASK_NAMES := ["idle", "piloting", "engineering", "trading",
	"loading", "unloading", "eating", "resting", "on_mission"]
const MAX_U8: int = 255
const MAX_U32: int = 4294967295

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func _numeric(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))

static func _uint(value: Variant, limit: int = MAX_U32) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0 and int(value) <= limit

static func _clamped_u8(value: Variant) -> int:
	## Rust f32::round().clamp(0.0,255.0) as u8: f32 is retained in
	## real ShipCrew; this rounded number is ONLY for display/wire.
	return clampi(int(round(float(value))), 0, MAX_U8)

static func crew_wire(crew: Variant, skills: Variant) -> Dictionary:
	## Rust ShipCrewSnapshot::default() with empty crew component.
	if crew == null:
		return {"ok": true, "crew": {
			"size": 0, "morale": 0, "fatigue": 0, "hunger": 0,
			"health": 0, "current_task": "", "wages_credits": 0}}
	if not (crew is Dictionary):
		return _fail("invalid_crew_component")
	if not _uint(crew.get("size", null)):
		return _fail("invalid_crew_size")
	for key in ["morale", "fatigue", "hunger", "health"]:
		if not _numeric(crew.get(key, null)):
			return _fail("invalid_crew_" + key)
	if typeof(crew.get("wages_credits", null)) != TYPE_INT:
		return _fail("invalid_crew_paid_wages")
	var task: String = str(crew.get("current_task", ""))
	if task not in CREW_TASK_NAMES:
		return _fail("invalid_crew_task")
	var result: Dictionary = {"size": crew["size"],
		"morale": _clamped_u8(crew["morale"]),
		"fatigue": _clamped_u8(crew["fatigue"]),
		"hunger": _clamped_u8(crew["hunger"]),
		"health": _clamped_u8(crew["health"]),
		"current_task": task, "wages_credits": crew["wages_credits"]}
	if skills != null:
		if not (skills is Dictionary):
			return _fail("invalid_crew_skills")
		var out := {}
		for key in ["navigation", "engineering", "trading", "combat"]:
			if not _uint(skills.get(key, null), MAX_U8):
				return _fail("invalid_crew_skill_" + key)
			out[key] = skills[key]
		result["skills"] = out
	return {"ok": true, "crew": result}

static func wire(facts: Dictionary) -> Dictionary:
	## Source facts snapshot must include actual Rust ECS identities:
	## identity:{id,name,class,faction_id,size}, position:
	## {system_id,location_name,docked_at,coordinates:{x,y}},
	## transit:null|Dictionary, cargo:{commodity_slug:u32},
	## cargo_capacity:u32, fuel, fuel_capacity, credits:i64,
	## ai:{current_goal,current_bt_action}, lifecycle, crew:?Dictionary,
	## skills:?Dictionary, fitting:?{modules,stats}, progression:?Dictionary,
	## faction_reputation:{faction:u8}.
	##
	## Fitting is the exact N51 adapter projection and progression is
	## the N101 adapter projection (including next_level_threshold).
	for key in ["identity", "position", "transit", "cargo", "cargo_capacity",
			"fuel", "fuel_capacity", "credits", "ai", "lifecycle", "crew",
			"skills", "fitting", "progression", "faction_reputation"]:
		if not facts.has(key):
			return _fail("missing_native_ship_fact:" + key)
	var identity: Variant = facts["identity"]
	var position: Variant = facts["position"]
	var ai: Variant = facts["ai"]
	var cargo: Variant = facts["cargo"]
	var lifecycle: Variant = facts["lifecycle"]
	var reputation: Variant = facts["faction_reputation"]
	if not (identity is Dictionary and position is Dictionary and ai is Dictionary and
			cargo is Dictionary and lifecycle is Dictionary and reputation is Dictionary):
		return _fail("invalid_native_ship_fact")
	if not Lifecycle._valid_lifecycle(lifecycle):
		return _fail("invalid_ship_lifecycle")
	for key in ["id", "name", "class", "faction_id", "size"]:
		if not (identity.get(key) is String):
			return _fail("invalid_ship_identity_" + key)
	if str(identity["id"]).is_empty() or str(identity["class"]).is_empty():
		return _fail("missing_ship_id_or_class")
	var size: String = str(identity["size"])
	if size not in SIZE_NAMES:
		return _fail("invalid_native_ship_size")
	var tier: int = SIZE_NAMES.find(size) + 1
	if not (position.get("system_id") is String):
		return _fail("invalid_ship_system")
	var location = position.get("location_name", null)
	if location != null and not (location is String):
		return _fail("invalid_location_name")
	var docked_at = position.get("docked_at", null)
	if docked_at != null and not (docked_at is String):
		return _fail("invalid_docked_entity")
	var coords = position.get("coordinates", null)
	if not (coords is Dictionary) or not _numeric(coords.get("x")) or not _numeric(coords.get("y")):
		return _fail("invalid_native_ship_coordinates")
	if facts["transit"] != null and not (facts["transit"] is Dictionary):
		return _fail("invalid_transit_component")
	if not _uint(facts["cargo_capacity"]) or not _numeric(facts["fuel"]) or 			not _numeric(facts["fuel_capacity"]) or typeof(facts["credits"]) != TYPE_INT:
		return _fail("invalid_native_ship_economy")
	var cargo_copy: Dictionary = {}
	for commodity in cargo:
		if not (commodity is String) or not _uint(cargo[commodity]):
			return _fail("invalid_native_cargo")
		cargo_copy[commodity] = cargo[commodity]
	for key in ["current_goal", "current_bt_action"]:
		if not ai.has(key):
			return _fail("missing_ship_ai:" + key)
	if not (ai["current_goal"] is String) or 			(ai["current_bt_action"] != null and not (ai["current_bt_action"] is String)):
		return _fail("invalid_native_ship_ai")
	var crew_projection := crew_wire(facts["crew"], facts["skills"])
	if not bool(crew_projection.get("ok", false)):
		return crew_projection
	var wire: Dictionary = {
		"id": identity["id"], "name": identity["name"], "class": identity["class"],
		"faction_id": identity["faction_id"],
		"system_id": position["system_id"], "size": size, "size_tier": tier,
		"location": location, "docked": docked_at != null,
		"transit": facts["transit"].duplicate(true) if facts["transit"] is Dictionary else null,
		"cargo": cargo_copy, "cargo_capacity": facts["cargo_capacity"],
		"fuel": facts["fuel"], "fuel_capacity": facts["fuel_capacity"],
		"credits": facts["credits"], "current_goal": ai["current_goal"],
		"current_bt": ai["current_bt_action"],
		"position": {"x": coords["x"], "y": coords["y"]},
		"broke_strikes": lifecycle["broke_strikes"],
		"hoard_strikes": lifecycle["hoard_strikes"],
		"idle_ticks": lifecycle["idle_ticks"],
		"crew": crew_projection["crew"]}
	var active = facts.get("active_contract_id", null)
	if active != null:
		if not (active is String):
			return _fail("invalid_native_active_contract_id")
		wire["active_contract_id"] = active
	var fitting = facts["fitting"]
	if fitting != null:
		if not (fitting is Dictionary) or not (fitting.get("modules") is Dictionary) or 				not (fitting.get("stats") is Dictionary):
			return _fail("invalid_native_fitting")
		wire["fitting"] = fitting.duplicate(true)
	var progression = facts["progression"]
	if progression != null:
		if not (progression is Dictionary):
			return _fail("invalid_native_progression")
		for key in ["level", "xp", "retrofit_points", "next_level_threshold"]:
			if not _uint(progression.get(key, null)):
				return _fail("invalid_native_progression_" + key)
		wire["progression"] = progression.duplicate(true)
	var r_copy := {}
	for faction in reputation:
		if not (faction is String) or not _uint(reputation[faction], MAX_U8):
			return _fail("invalid_native_reputation")
		r_copy[faction] = reputation[faction]
	if not r_copy.is_empty():
		wire["faction_reputation"] = r_copy
	# The native snapshot is a wire projection of actual world data. It
	# must NEVER be used to restore the authoritative ship/world state.
	return {"ok": true, "ship": wire}
