extends RefCounted
## Frozen Rust: native/crates/sim_core/src/agents/ship/actions.rs
## Decision-phase only: returns commands for authoritative apply, never transfers cargo or CR.
const SUCCESS := "success"
const RUNNING := "running"
const FAILURE := "failure"
const CREW_REST_TARGET := 80.0
const MAX_REST_TICKS_BASE := 300
const DOCK_WAIT_WITH_CONTRACT := 150
const DOCK_WAIT_DEFAULT := 60
const DOCK_WAIT_LOW_MORALE := 30
const DOCK_WAIT_LOW_MORALE_THRESHOLD := 40.0

static func _result(status: String, state: Dictionary, commands: Array = [], flags: Dictionary = {}) -> Dictionary:
	return {"status": status, "state": state, "commands": commands, "flags": flags}

## state fields mirror ShipEconomy timers; caller persists them with ship state.
## ship fields: location, docked_at, in_transit, morale, active_contract_id.
## tick_multiplier is Rust TickConfig.tick_multiplier(), supplied by caller.
static func step(action: Dictionary, ship: Dictionary, previous_state: Dictionary, tick: int, tps: int, tick_multiplier: int) -> Dictionary:
	var state := previous_state.duplicate(true)
	var kind: String = str(action.get("kind", ""))
	var location: String = str(ship.get("location", ""))
	var docked: bool = ship.get("docked_at", null) != null
	var in_transit: bool = bool(ship.get("in_transit", false))
	var mult := maxi(1, tick_multiplier)
	match kind:
		"idle":
			return _result(SUCCESS, state)
		"construct":
			if location == str(action.get("location", "")) and docked and not in_transit:
				return _result(RUNNING, state)
			return _result(FAILURE, state)
		"dock_dwell":
			var start: int = int(state.get("dock_dwell_start_tick", tick))
			state["dock_dwell_start_tick"] = start
			if maxi(0, tick - start) >= maxi(0, int(action.get("seconds", 0))) * maxi(1, tps):
				state.erase("dock_dwell_start_tick")
				return _result(SUCCESS, state)
			return _result(RUNNING, state)
		"rest":
			var start: int = int(state.get("rest_start_tick", tick))
			state["rest_start_tick"] = start
			var timed_out: bool = maxi(0, tick - start) >= MAX_REST_TICKS_BASE * mult
			if float(ship.get("morale", 0.0)) >= CREW_REST_TARGET or timed_out:
				state.erase("rest_start_tick")
				return _result(SUCCESS, state, [], {"rest_timed_out": timed_out and float(ship.get("morale", 0.0)) < CREW_REST_TARGET})
			return _result(RUNNING, state)
		"dock", "dock_at_shipyard":
			if docked:
				state.erase("dock_attempt_start_tick")
				return _result(SUCCESS, state)
			if location.is_empty():
				state.erase("dock_attempt_start_tick")
				return _result(FAILURE, state)
			var start: int = int(state.get("dock_attempt_start_tick", tick))
			state["dock_attempt_start_tick"] = start
			var morale: float = float(ship.get("morale", 0.0))
			var budget := DOCK_WAIT_DEFAULT
			if kind == "dock" and ship.get("active_contract_id", null) != null:
				budget = DOCK_WAIT_WITH_CONTRACT
			elif morale < DOCK_WAIT_LOW_MORALE_THRESHOLD:
				budget = DOCK_WAIT_LOW_MORALE
			if maxi(0, tick - start) >= budget * mult:
				state.erase("dock_attempt_start_tick")
				return _result(FAILURE, state)
			return _result(RUNNING, state, [{"type": "request_dock", "location": location, "preferred_facility_type": "shipyard" if kind == "dock_at_shipyard" else null}])
		"undock":
			if not docked:
				return _result(SUCCESS, state)
			if location.is_empty():
				return _result(FAILURE, state)
			return _result(SUCCESS, state, [{"type": "request_undock", "location": location, "facility_id": ship.get("docked_at")}])
		_:
			# Buy, sell, mine, refuel, gate jump, refit and contracts need authoritative
			# snapshots and apply-phase receipts. Unknown leaves must fail closed.
			return _result(FAILURE, state, [], {"reason": "requires_authoritative_action_adapter"})
