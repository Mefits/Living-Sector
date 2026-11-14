extends RefCounted
## N148 — frozen sim_server/engine/apply.rs + drains.rs adaptive-fleet
## lifecycle queue and policy: DATA-ONLY projection.
## Never call SQL, mint a replacement hull or despawn a ship in Phase 1.
## The exclusive native server owner performs admin_remove_ship, persistence
## and asset clean-up BEFORE confirming the removal.

const REASONS := ["bankruptcy", "stagnation"]
const MAX_I64: int = 9223372036854775807

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func stage_decommission(pending: Array, sim_command: Dictionary) -> Dictionary:
	## engine/apply.rs::DecommissionShip -> AgentStore.pending_decommissions.
	## N146 CommandBuffer alone stages commands; here Apply transcribes
	## DecommissionShip exactly once per N146 command occurrence. Native
	## Rust has no dedup here, so this function also doesn't invent one.
	if str(sim_command.get("kind", "")) != "decommission_ship":
		return _fail("not_native_decommission_command")
	var reason: String = str(sim_command.get("reason", ""))
	var ship = sim_command.get("ship", null)
	if reason not in REASONS or not (ship is String) or str(ship).is_empty():
		return _fail("invalid_decommission_command")
	var result := pending.duplicate(true)
	result.append({"entity": ship, "reason": reason})
	return {"ok": true, "pending": result}

static func drain_pending_decommissions(pending: Array, currently_live: Dictionary) -> Dictionary:
	## Native Rust std::mem::take on the queue; actual removal is async.
	## If a repeated source request refers to an entity already missing,
	## the Rust drain skips it. This returns JUST owned native removals
	## to the exclusive server apply; no fake disappearance from world.
	var valid: Array[Dictionary] = []
	for req in pending:
		if not (req is Dictionary):
			return _fail("invalid_decommission_queue")
		var ship: String = str(req.get("entity", ""))
		var reason: String = str(req.get("reason", ""))
		if ship.is_empty() or reason not in REASONS:
			return _fail("invalid_decommission_request")
		if currently_live.has(ship):
			var live = currently_live[ship]
			if not (live is Dictionary) or not (live.get("ship_id") is String) or 					not (live.get("faction_id") is String):
				return _fail("invalid_ship_identity")
			valid.append({"entity": ship, "ship_id": str(live["ship_id"]),
				"faction_id": str(live["faction_id"]), "reason": reason,
				"requires": "authoritative_admin_remove_ship"})
	return {"ok": true, "drained": valid, "pending_after": []}

static func on_authoritative_ship_removed(req: Dictionary, result: Dictionary,
		tick: int, auto_replace_retired_ships: bool) -> Dictionary:
	## sim_server/engine/drains.rs::drain_pending_decommissions:
	## 1. Snapshot ship/faction id before despawn.
	## 2. Await admin_remove_ship + DB persistence.
	## 3. Check ship_by_id no longer contains id; otherwise skip.
	## 4. Patch last ship_decommissioned event's reason.
	## 5. Legacy world may schedule delayed free replacement.
	##    Genesis (finite hulls) emits fleet_loss_unreplaced.
	##
	## A "trusted" string in an arbitrary UI dict is NOT an authoritative
	## receipt. This function may only be called by engine code after
	## it has really performed (1)-(3). It does not delete a ship.
	var reason: String = str(req.get("reason", ""))
	var ship_id: String = str(req.get("ship_id", ""))
	var faction: String = str(req.get("faction_id", ""))
	if reason not in REASONS or ship_id.is_empty() or faction.is_empty() or tick < 0:
		return _fail("invalid_retirement_request")
	if not bool(result.get("trusted_internal_apply", false)) or 			not bool(result.get("admin_remove_succeeded", false)) or 			bool(result.get("ship_still_present", true)) or 			str(result.get("ship_id", "")) != ship_id:
		return _fail("actual_removed_ship_receipt_required")
	var out_events: Array[Dictionary] = []
	# Event is a narrow patch to the engine's EXISTING event, not a
	# second "decommission" row or new removal command.
	var patch := {"kind": "patch_last_decommission_event",
		"expected_kind": "ship_decommissioned", "reason": reason,
		"ship_id": ship_id}
	if auto_replace_retired_ships:
		# Native 300 + (tick % 300), deterministic 300..599; spawning
		# is deferred, and only if WorldTuning permits free replacement.
		var delay: int = 300 + (tick % 300)
		var spawn_at: int = mini(MAX_I64, tick + delay)
		return {"ok": true, "event_patch": patch, "events": out_events,
			"pending_respawn": {"spawn_at_tick": spawn_at,
				"prefer_faction": faction}}
	out_events.append({"kind": "fleet_loss_unreplaced",
		"ship_id": ship_id, "faction_id": faction,
		"reason": reason, "tick": tick})
	return {"ok": true, "event_patch": patch, "events": out_events,
		"pending_respawn": null}

static func due_respawns(queue: Array, tick: int, auto_replace_retired_ships: bool) -> Dictionary:
	## engine/drains.rs::drain_pending_respawns (first half only).
	## If world policy changes to FINITE hulls, ALL previous legacy
	## free respawn requests are suppressed, not converted to free ships.
	if tick < 0:
		return _fail("invalid_tick")
	var ready: Array[Dictionary] = []
	var keep: Array[Dictionary] = []
	var events: Array[Dictionary] = []
	for row in queue:
		if not (row is Dictionary) or typeof(row.get("spawn_at_tick")) != TYPE_INT or 				int(row["spawn_at_tick"]) < 0:
			return _fail("invalid_respawn_request")
		if row.get("prefer_faction") != null and not (row.get("prefer_faction") is String):
			return _fail("invalid_respawn_faction")
		var req: Dictionary = row.duplicate(true)
		if not auto_replace_retired_ships:
			events.append({"kind": "free_respawn_suppressed",
				"faction_id": row.get("prefer_faction"),
				"scheduled_at_tick": row["spawn_at_tick"], "tick": tick})
		elif int(req["spawn_at_tick"]) <= tick:
			ready.append(req)
		else:
			keep.append(req)
	return {"ok": true, "ready": ready, "pending_after": keep,
		"events": events,
		"requires": "native_db_spawn_replacement_ship" if auto_replace_retired_ships else ""}
