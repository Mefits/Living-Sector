extends RefCounted
## N148 — frozen Rust Galaxy 0.6.7 ShipLifecycle adaptive-fleet source.
## components.rs::ShipLifecycle/STRIKE_* and behavior.rs:1024-1074
## This is an isolated per-active-ship pure transition: no physical despawn,
## no server command apply, no free hull spawn and no second economic ledger.

const MAX_U8: int = 255
const MAX_U32: int = 4294967295
const STRIKE_CHECK_INTERVAL_BASE: int = 500
const MAX_STRIKES: int = 3
const BROKE_CREDITS_THRESHOLD: int = 500
const BROKE_RECOVERY_THRESHOLD: int = 5000
const HOARD_CREDITS_THRESHOLD: int = 200000
const HOARD_IDLE_THRESHOLD: int = 500

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func default_lifecycle() -> Dictionary:
	return {"broke_strikes": 0, "hoard_strikes": 0, "idle_ticks": 0,
		"dirty": false}

static func _valid_lifecycle(lifecycle: Dictionary) -> bool:
	for key in ["broke_strikes", "hoard_strikes", "idle_ticks"]:
		if typeof(lifecycle.get(key, null)) != TYPE_INT:
			return false
	if int(lifecycle["broke_strikes"]) < 0 or int(lifecycle["broke_strikes"]) > MAX_U8:
		return false
	if int(lifecycle["hoard_strikes"]) < 0 or int(lifecycle["hoard_strikes"]) > MAX_U8:
		return false
	if int(lifecycle["idle_ticks"]) < 0 or int(lifecycle["idle_ticks"]) > MAX_U32:
		return false
	return typeof(lifecycle.get("dirty", false)) == TYPE_BOOL

static func lifecycle_step(lifecycle: Dictionary, ship: Dictionary,
		tick: int, tick_multiplier: int, actually_fired: bool = true) -> Dictionary:
	## Rust decide_and_act processes only ships passing the native LOD gate.
	## The tick loop itself owns LOD and advances once per ACTIVE ship step.
	## idle increments ONCE PER CALL, not by skipped LOD ticks.
	## The goal here must be the ACTUAL current goal after replan (N80),
	## not a predictive candidate or pre-decision desired goal.
	if not _valid_lifecycle(lifecycle):
		return _fail("invalid_ship_lifecycle")
	if tick < 0 or tick_multiplier < 0:
		return _fail("invalid_ship_tick")
	for key in ["current_goal", "credits", "cargo_used", "active_contract_id", "ship_entity"]:
		if not ship.has(key):
			return _fail("missing_ship_snapshot:" + key)
	if not (ship["current_goal"] is String) or typeof(ship["credits"]) != TYPE_INT or 			typeof(ship["cargo_used"]) != TYPE_INT or int(ship["cargo_used"]) < 0:
		return _fail("invalid_ship_economic_state")
	var active_contract = ship["active_contract_id"]
	if active_contract != null and not (active_contract is String):
		return _fail("invalid_active_contract")
	if not (ship["ship_entity"] is String) or str(ship["ship_entity"]).is_empty():
		return _fail("invalid_native_ship_entity")
	## N146 stages SimCommand::DecommissionShip with native entity handle.
	## This is not an admin removal: only a native engine apply can queue it.
	var updated := lifecycle.duplicate(true)
	var commands: Array[Dictionary] = []
	if not actually_fired:
		return {"ok": true, "lifecycle": updated, "commands": commands,
			"strike_due": false, "reason": "lod_skipped"}
	if str(ship["current_goal"]).begins_with("idle"):
		updated["idle_ticks"] = mini(MAX_U32, int(updated["idle_ticks"]) + 1)
	else:
		updated["idle_ticks"] = 0
	# Rust behavior.rs cadence: tick % (500 * multiplier) == 0 only
	# when the product is > 0; multiplier=0 therefore skips strikes.
	var interval: int = STRIKE_CHECK_INTERVAL_BASE * tick_multiplier
	var due: bool = interval > 0 and tick % interval == 0
	if due:
		# A starving ship with actual cargo/committed work avoids a strike;
		# the counter resets only after credits recover to >= 5000.
		if int(ship["credits"]) < BROKE_CREDITS_THRESHOLD and 				int(ship["cargo_used"]) == 0 and active_contract == null:
			updated["broke_strikes"] = mini(MAX_U8, int(updated["broke_strikes"]) + 1)
		elif int(ship["credits"]) >= BROKE_RECOVERY_THRESHOLD:
			updated["broke_strikes"] = 0
		# Native Rust does not auto-decay hoard strikes when idle ends;
		# only a confirmed delivery resets hoard_strikes to 0.
		if int(ship["credits"]) > HOARD_CREDITS_THRESHOLD and 				int(updated["idle_ticks"]) > HOARD_IDLE_THRESHOLD:
			updated["hoard_strikes"] = mini(MAX_U8, int(updated["hoard_strikes"]) + 1)
		# Bankruptcy beats stagnation if both strike caps were reached.
		# Native source emits another command on next due tick even if
		# same ship hasn't yet been removed. Do not invent dedup here.
		var reason := ""
		if int(updated["broke_strikes"]) >= MAX_STRIKES:
			reason = "bankruptcy"
		elif int(updated["hoard_strikes"]) >= MAX_STRIKES:
			reason = "stagnation"
		if reason != "":
			commands.append({"kind": "decommission_ship",
				"ship": ship["ship_entity"], "reason": reason})
	updated["dirty"] = true
	return {"ok": true, "lifecycle": updated, "commands": commands,
		"strike_due": due, "reason": ""}

static func after_confirmed_delivery(lifecycle: Dictionary, receipt: Dictionary) -> Dictionary:
	## native engine/apply.rs:1130-1134: clears hoard strikes AFTER success.
	## The real Apply/contract delivery must already have returned a
	## verified success; no caller should pass an untrusted UI receipt.
	if not _valid_lifecycle(lifecycle):
		return _fail("invalid_ship_lifecycle")
	if not bool(receipt.get("trusted_internal_apply", false)) or 			not bool(receipt.get("delivery_succeeded", false)) or 			not (receipt.get("ship_entity") is String) or 			str(receipt.get("ship_entity")).is_empty():
		return _fail("actual_paid_delivery_receipt_required")
	var updated := lifecycle.duplicate(true)
	updated["hoard_strikes"] = 0
	## The original Apply code does not explicitly reset idle_ticks or
	## broke_strikes and doesn't change dirty here; preserve both.
	return {"ok": true, "lifecycle": updated, "reason": ""}
