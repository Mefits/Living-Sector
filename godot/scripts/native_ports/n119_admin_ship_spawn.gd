extends RefCounted
## Exact source boundary: engine/admin.rs admin_spawn_ship, after external DB INSERT.
## Not a free shipyard build: requires a committed DB row and externally paid authorization.
static func hydrate_after_insert(payload: Dictionary, class_cfg: Dictionary, fitting: Dictionary, existing_ids: Dictionary) -> Dictionary:
	var id := str(payload.get("agent_id", ""))
	var db_id := int(payload.get("db_id", 0))
	if id.is_empty() or db_id <= 0 or existing_ids.has(id):
		return {"ok": false, "reason": "missing_db_insert_or_duplicate"}
	if not bool(payload.get("db_insert_confirmed", false)):
		return {"ok": false, "reason": "db_insert_unconfirmed"}
	var cargo_mult := float(fitting.get("cargo_capacity_mult", 1.0))
	var speed_mult := float(fitting.get("speed_mult", 1.0))
	var size_mult := float(fitting.get("size_speed_multiplier", 1.0))
	if not is_finite(cargo_mult) or not is_finite(speed_mult) or not is_finite(size_mult):
		return {"ok": false, "reason": "invalid_fitting"}
	var cargo_cap := maxi(0, int(roundf(int(class_cfg.get("cargo_capacity", 500)) * cargo_mult)))
	var fuel_cap := float(class_cfg.get("fuel_capacity", 100.0))
	if fuel_cap <= 0.0 or not is_finite(fuel_cap):
		return {"ok": false, "reason": "invalid_fuel"}
	var location := str(payload.get("location_name", ""))
	var klass := str(payload.get("class", ""))
	var ship := {
		"identity": {"db_id": db_id, "id": id, "name": str(payload.get("name", id)),
			"class": klass, "faction_id": str(payload.get("faction_id", "")),
			"size": str(class_cfg.get("default_size", "medium"))},
		"position": {"location_name": location, "docked_at": null, "system_id": "",
			"universe_offset": payload.get("universe_offset", Vector2.ZERO),
			"position": payload.get("position", Vector2.ZERO)},
		"transit": {"transit": null},
		"cargo": {"cargo": {}, "capacity": cargo_cap, "cargo_age": {}, "cargo_origin": {}},
		"fuel": {"fuel": fuel_cap, "fuel_capacity": fuel_cap,
			"fuel_consumption_rate": float(class_cfg.get("fuel_consumption_base", 0.05)),
			"speed_modifier": float(class_cfg.get("speed_modifier", 1.0)) * speed_mult * size_mult},
		"economy": {"credits": int(payload.get("credits", 0)), "efficiency": 1.0,
			"active_contract_id": null, "faction_reputation": {}, "transaction": {},
			"dock_dwell_start_tick": null, "rest_start_tick": null, "dock_attempt_start_tick": null},
		"ai": {"personality_class": klass, "current_goal": "idle",
			"current_bt": null, "current_goal_score": 0.0, "last_plan_tick": 0},
		"memory": {"price_knowledge": {}, "visited": [location], "recent_systems": [],
			"route_performance": {}, "contract_rejections": {}},
		"lifecycle": {"broke_strikes": 0, "hoard_strikes": 0, "idle_ticks": 0, "dirty": true},
		"crew": {"size": int(class_cfg.get("crew_size", 5)), "hunger": 10.0,
			"morale": 70.0, "fatigue": 10.0, "health": 100.0,
			"wages_credits": 0, "current_task": "Idle", "dirty": false},
		"crew_roles": class_cfg.get("crew_roles", []),
		"fitting": fitting.duplicate(true), "progression": {"experience": 0},
		"lod": {"mode": "active"}
	}
	return {"ok": true, "ship": ship, "event": {"kind": "ship_spawned",
		"id": id, "db_id": db_id, "class": klass, "location": location, "reason": "admin"}}
