extends RefCounted
## N138 — Frozen Rust ship/mod.rs tick_crew welfare rules, component-only.
## NO food consumption or wage payment. Those belong to N72 and the Phase-2
## exclusive ShipCrew/ShipCargo/ShipEconomy commit, never a second ledger.
const MORALE_INTERVAL_BASE: int = 5
const MORALE_DECAY_BASE: float = 0.5
const MORALE_RECOVERY_DOCKED: float = 6.0
const MORALE_RECOVERY_RESTING: float = 8.0
const HUNGER_MORALE_PENALTY_THRESHOLD: float = 60.0
const FATIGUE_MORALE_PENALTY_THRESHOLD: float = 70.0
const EAT_THRESHOLD: float = 55.0
const REST_THRESHOLD: float = 65.0
const SHORE_LEAVE_TRIGGER: float = 50.0
const SHORE_LEAVE_TARGET: float = 100.0
const LEGACY_REST_GOAL_TRIGGER: float = 15.0
const LEGACY_REST_TARGET: float = 80.0
const MAX_REST_TICKS_BASE: int = 300
const DOCK_WAIT_WITH_CONTRACT: int = 150
const DOCK_WAIT_DEFAULT: int = 60
const DOCK_WAIT_LOW_MORALE: int = 30
const DOCK_WAIT_LOW_MORALE_THRESHOLD: float = 40.0
const MAX_I64: int = 9223372036854775807
const TASKS := ["idle", "piloting", "engineering", "trading", "loading", "unloading",
	"eating", "resting", "on_mission"]

static func _finite_welfare(crew: Dictionary) -> bool:
	for field in ["hunger", "fatigue", "morale", "health"]:
		if not crew.has(field) or not is_finite(float(crew[field])):
			return false
		if float(crew[field]) < 0.0 or float(crew[field]) > 100.0:
			return false
	if str(crew.get("current_task", "")) not in TASKS:
		return false
	if not crew.has("size") or int(crew["size"]) < 0:
		return false
	return true

static func _result(crew: Dictionary, phase: String, reason: String = "") -> Dictionary:
	return {"ok": reason == "", "reason": reason,
		"phase": phase, "crew": crew.duplicate(true)}

static func morale_after_decay(crew: Dictionary, docked: bool, tick: int, multiplier: int) -> Dictionary:
	## Exact Rust order: decay (N72) -> this morale check -> physical food
	## -> task switch -> physical wages -> final efficiency.
	## 'crew' contains authoritative hunger/fatigue values AFTER decay,
	## but BEFORE any eating this tick.
	if tick < 0 or multiplier <= 0 or not _finite_welfare(crew):
		return _result(crew, "morale", "invalid_input")
	var out := crew.duplicate(true)
	var interval := MORALE_INTERVAL_BASE * multiplier
	if tick % interval != 0:
		return _result(out, "morale")
	var hunger := float(out["hunger"])
	var fatigue := float(out["fatigue"])
	var health := float(out["health"])
	var morale := float(out["morale"])
	var resting := str(out["current_task"]) == "resting"
	var penalty: float = 0.0
	if docked:
		if health < 50.0:
			penalty = -2.0
	elif hunger > HUNGER_MORALE_PENALTY_THRESHOLD:
		penalty = -3.0
	elif fatigue > FATIGUE_MORALE_PENALTY_THRESHOLD:
		penalty = -2.0
	elif health < 50.0:
		penalty = -4.0
	var recovery: float = 0.0
	if docked and resting:
		recovery = MORALE_RECOVERY_RESTING
	elif docked or resting:
		# Non-docked resting receives the FULL docked bonus in frozen Rust.
		recovery = MORALE_RECOVERY_DOCKED
	var drift: float = -MORALE_DECAY_BASE if morale > 50.0 else MORALE_DECAY_BASE
	out["morale"] = clampf(morale + penalty + recovery + drift, 0.0, 100.0)
	out["dirty"] = true
	return _result(out, "morale")

static func primary_task(roles: Array, in_transit: bool) -> String:
	## Frozen Rust exact priority (pilot never "piloting" when stationary).
	if in_transit:
		if "pilot" in roles:
			return "piloting"
		if "engineer" in roles:
			return "engineering"
		if "trader" in roles:
			return "trading"
		return "idle"
	if "trader" in roles:
		return "trading"
	if "engineer" in roles:
		return "engineering"
	return "idle"

static func task_after_meal(crew: Dictionary, roles: Array, in_transit: bool) -> Dictionary:
	## Called AFTER real N72 meal debit/hunger reduction, never eats by itself.
	## Strict < and > keep Rust's boundary hysteresis.
	if not _finite_welfare(crew):
		return _result(crew, "task", "invalid_input")
	var out := crew.duplicate(true)
	var old_task: String = str(out["current_task"])
	var hunger: float = float(out["hunger"])
	var fatigue: float = float(out["fatigue"])
	if hunger > EAT_THRESHOLD:
		out["current_task"] = "eating"
	elif fatigue > REST_THRESHOLD:
		out["current_task"] = "resting"
	else:
		var refresh := ((old_task == "eating" or old_task == "resting") and
			hunger < EAT_THRESHOLD and fatigue < REST_THRESHOLD) or old_task == "idle" or (
			in_transit and old_task != "piloting")
		if refresh:
			out["current_task"] = primary_task(roles, in_transit)
	out["dirty"] = true
	return _result(out, "task")

static func efficiency(crew: Dictionary) -> float:
	## Rust ShipCrew::efficiency: health*0.6 + morale*0.4, floor 0.1.
	if not _finite_welfare(crew):
		return NAN
	return clampf(float(crew["health"]) / 100.0 * 0.6 +
		float(crew["morale"]) / 100.0 * 0.4, 0.1, 1.0)

static func economy_efficiency_after_wages(crew: Dictionary, economy: Dictionary) -> Dictionary:
	## Called AFTER N72 wage transfer/failed-wage penalty. Never debit credits.
	if not _finite_welfare(crew) or not economy.has("credits"):
		return {"ok": false, "reason": "invalid_input", "economy": economy.duplicate(true)}
	var updated := economy.duplicate(true)
	updated["efficiency"] = efficiency(crew)
	return {"ok": true, "reason": "", "economy": updated}

static func needs_shore_leave(crew: Dictionary) -> bool:
	return _finite_welfare(crew) and float(crew["morale"]) < SHORE_LEAVE_TRIGGER

static func shore_leave_complete(crew: Dictionary) -> bool:
	return _finite_welfare(crew) and float(crew["morale"]) >= SHORE_LEAVE_TARGET

static func legacy_rest_goal_needed(crew: Dictionary) -> bool:
	return _finite_welfare(crew) and float(crew["morale"]) < LEGACY_REST_GOAL_TRIGGER

static func legacy_rest_action_completed(crew: Dictionary) -> bool:
	return _finite_welfare(crew) and float(crew["morale"]) >= LEGACY_REST_TARGET

static func dock_wait_budget(crew: Dictionary, has_active_contract: bool, multiplier: int) -> int:
	## The Rust BT-specific calculation is outside this pure source policy;
	## the 150/30/60 native base tick thresholds are preserved.
	if multiplier < 1 or not _finite_welfare(crew):
		return -1
	var base := DOCK_WAIT_DEFAULT
	if has_active_contract:
		base = DOCK_WAIT_WITH_CONTRACT
	elif float(crew["morale"]) < DOCK_WAIT_LOW_MORALE_THRESHOLD:
		base = DOCK_WAIT_LOW_MORALE
	return min(MAX_I64, base * multiplier)

static func max_rest_ticks(multiplier: int) -> int:
	if multiplier < 1:
		return -1
	return min(MAX_I64, MAX_REST_TICKS_BASE * multiplier)
