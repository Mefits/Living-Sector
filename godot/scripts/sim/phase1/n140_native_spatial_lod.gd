extends RefCounted
## N140: Rust simulation/lod.rs AgentLod state machine and distance tiers.
## Pure snapshots: no simulation ticks, cargo, facilities, markets or agent AI executed here.
const MAX_U32: int = 4294967295
const MAX_I64: int = 9223372036854775807
const RECOMPUTE_INTERVAL_BASE: int = 50
const STANDARD_DIVISORS := [1, 2, 5, 10, 20, 50]

static func new_cursor() -> Dictionary:
	## Rust AgentLod::new/default.
	return {"divisor": 1, "next_tick": 0}

static func _cursor_ok(cursor: Dictionary) -> bool:
	if not cursor.has("divisor") or not cursor.has("next_tick"):
		return false
	var divisor: int = int(cursor["divisor"])
	var next_tick: int = int(cursor["next_tick"])
	return divisor >= 0 and divisor <= 255 and next_tick >= 0

static func try_fire(cursor: Dictionary, tick: int) -> Dictionary:
	## Exact native Rust: skip when tick<next_tick; when firing the skipped
	## count is (tick - saturating_sub(next_tick, max(1,divisor))).max(1) as u32.
	## Do not coalesce repeated firings; caller must fire at most once per
	## agent per real tick and exclusively on native SHIPS.
	if not _cursor_ok(cursor) or tick < 0:
		return {"ok": false, "reason": "invalid_cursor_or_tick", "fired": false, "skipped_ticks": 0,
			"cursor": cursor.duplicate(true)}
	var original := cursor.duplicate(true)
	var next_tick: int = int(cursor["next_tick"])
	if tick < next_tick:
		return {"ok": true, "reason": "", "fired": false, "skipped_ticks": 0, "cursor": original}
	var divisor: int = maxi(1, int(cursor["divisor"]))
	var last_fire := maxi(0, next_tick - divisor)
	var skipped: int = (maxi(1, tick - last_fire)) & MAX_U32
	original["next_tick"] = mini(MAX_I64, tick + divisor)
	return {"ok": true, "reason": "", "fired": true, "skipped_ticks": skipped, "cursor": original}

static func set_divisor(cursor: Dictionary, divisor: int, tick: int) -> Dictionary:
	## The native function accepts any u8 divisor (not only standard tiers).
	if not _cursor_ok(cursor) or divisor < 0 or divisor > 255 or tick < 0:
		return {"ok": false, "reason": "invalid_cursor_divisor_or_tick", "cursor": cursor.duplicate(true)}
	var updated := cursor.duplicate(true)
	var d := maxi(1, divisor)
	if d == int(updated["divisor"]):
		return {"ok": true, "reason": "", "cursor": updated}
	updated["divisor"] = d
	updated["next_tick"] = tick if int(updated["next_tick"]) <= tick else mini(MAX_I64, tick + d)
	return {"ok": true, "reason": "", "cursor": updated}

static func divisor_for_distance_sq(distance_sq: float, radius: float) -> int:
	## Distance tier uses squared distance and r=max(radius, 0.01).
	## Exact native inclusive boundaries: r,2r,5r,10r,20r,then 50.
	var r: float = maxf(radius, 0.01)
	var rsq: float = r * r
	if distance_sq <= rsq:
		return 1
	if distance_sq <= 4.0 * rsq:
		return 2
	if distance_sq <= 25.0 * rsq:
		return 5
	if distance_sq <= 100.0 * rsq:
		return 10
	if distance_sq <= 400.0 * rsq:
		return 20
	return 50

static func divisor_for_position(pos: Vector2, observers: Array) -> int:
	## Important Rust subtlety: picks the physically NEAREST observer
	## before comparing its own radius; it does NOT choose min divisor
	## among all observers (or normalize distance by their radii).
	if observers.is_empty():
		return 1 # No client/headless: everyone runs at full detail.
	var nearest_sq := INF
	var nearest_radius := 1.0
	for observer in observers:
		if not observer is Dictionary:
			continue
		if not observer.has("position") or not observer.has("radius"):
			continue
		var p = observer["position"]
		if not p is Vector2:
			continue
		var offset := pos - (p as Vector2)
		var sq: float = offset.length_squared()
		if sq < nearest_sq:
			nearest_sq = sq
			nearest_radius = float(observer["radius"])
	return divisor_for_distance_sq(nearest_sq, nearest_radius)

static func should_recompute(tick: int, tick_multiplier: int) -> bool:
	## Policy helper only: actual authoritative TickRunner chooses cadence.
	return tick >= 0 and tick_multiplier > 0 and tick % (RECOMPUTE_INTERVAL_BASE * tick_multiplier) == 0

static func stats_for_agents(agents: Dictionary) -> Dictionary:
	var result := {"d1": 0, "d2": 0, "d5": 0, "d10": 0, "d20": 0, "d50": 0, "other": 0, "total": 0}
	var keys := {1: "d1", 2: "d2", 5: "d5", 10: "d10", 20: "d20", 50: "d50"}
	for id in agents:
		var entry = agents[id]
		if not entry is Dictionary or not entry.get("lod") is Dictionary:
			continue
		var divisor := int(entry["lod"].get("divisor", 0))
		var key: String = keys.get(divisor, "other")
		result[key] += 1
		result["total"] += 1
	return result

static func recompute(agents: Dictionary, observers: Array, tick: int) -> Dictionary:
	## Mirrors tick_lod_recompute: only agents with KNOWN positions are
	## processed and counted; unpositioned agents retain their old divisor.
	## All agents (including facility/population) may carry a cursor, but
	## downstream SHIP tick is the only native cursor consumer.
	if tick < 0:
		return {"ok": false, "reason": "invalid_tick", "agents": agents.duplicate(true), "stats": {}}
	var updated := agents.duplicate(true)
	var result := {"d1": 0, "d2": 0, "d5": 0, "d10": 0, "d20": 0, "d50": 0, "other": 0, "total": 0}
	var keys := {1: "d1", 2: "d2", 5: "d5", 10: "d10", 20: "d20", 50: "d50"}
	var ids = updated.keys()
	ids.sort()
	for id in ids:
		var agent = updated[id]
		if not agent is Dictionary or not agent.get("lod") is Dictionary:
			continue
		# No position means Rust 'continue': do not include in stats.
		if not agent.get("position") is Vector2:
			continue
		var cursor: Dictionary = agent["lod"]
		if not _cursor_ok(cursor):
			return {"ok": false, "reason": "invalid_agent_cursor:" + str(id),
				"agents": agents.duplicate(true), "stats": {}}
		var new_divisor := divisor_for_position(agent["position"], observers)
		var staged := set_divisor(cursor, new_divisor, tick)
		if not bool(staged.get("ok", false)):
			return {"ok": false, "reason": "set_divisor_failed:" + str(id),
				"agents": agents.duplicate(true), "stats": {}}
		agent["lod"] = staged["cursor"]
		updated[id] = agent
		var category: String = keys.get(new_divisor, "other")
		result[category] += 1
		result["total"] += 1
	return {"ok": true, "reason": "", "agents": updated, "stats": result}

static func ship_gate(agents: Dictionary, ship_ids: Array, tick: int) -> Dictionary:
	## One native ship pass obtains a map ship_id -> skipped_ticks.
	## Never advance facility/population cursors in this ship pass.
	## An owned, persisted cursor must be committed exactly once per
	## native tick, before transit, prices, crew, decision/action.
	var updated := agents.duplicate(true)
	var fires := {}
	if tick < 0:
		return {"ok": false, "reason": "invalid_tick", "agents": updated, "fires": fires}
	var ordered = ship_ids.duplicate()
	ordered.sort()
	var visited := {}
	for id in ordered:
		if visited.has(id):
			return {"ok": false, "reason": "duplicate_ship_id:" + str(id),
				"agents": agents.duplicate(true), "fires": {}}
		visited[id] = true
		if not updated.has(id):
			return {"ok": false, "reason": "missing_ship:" + str(id), "agents": agents.duplicate(true), "fires": {}}
		var ship = updated[id]
		if not (ship is Dictionary):
			return {"ok": false, "reason": "malformed_ship:" + str(id), "agents": agents.duplicate(true), "fires": {}}
		if not ship.has("lod") or ship["lod"] == null:
			fires[id] = 1 # Rust ship with NO AgentLod ticks every real tick.
			continue
		if not ship["lod"] is Dictionary:
			return {"ok": false, "reason": "malformed_lod:" + str(id),
				"agents": agents.duplicate(true), "fires": {}}
		var res := try_fire(ship["lod"], tick)
		if not bool(res.get("ok", false)):
			return {"ok": false, "reason": str(res.get("reason", "invalid_cursor")) + ":" + str(id),
				"agents": agents.duplicate(true), "fires": {}}
		ship["lod"] = res["cursor"]
		updated[id] = ship
		if bool(res.get("fired", false)):
			fires[id] = int(res["skipped_ticks"])
	return {"ok": true, "reason": "", "agents": updated, "fires": fires}
