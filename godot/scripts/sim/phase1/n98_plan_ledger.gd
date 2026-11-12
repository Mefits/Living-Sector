extends RefCounted
## N98 — Rust strategy/planning/ledger.rs. Pure durable plan state.
## The native dispatcher owns orders; Prepared MUST reconcile by dispatch_key.
const SCHEMA_VERSION := 1
const PLANNED := "planned"
const PREPARED := "prepared"
const SUBMITTED := "submitted"
const RUNNING := "running"
const SUCCEEDED := "succeeded"
const FAILED := "failed"
const CANCELLED := "cancelled"

static func create_plan(snapshot: Dictionary, goal: Dictionary, proposal: Dictionary, plan_id: String) -> Dictionary:
	if plan_id.is_empty() or str(proposal.get("status", "")) != "ready":
		return {"error": "invalid_plan"}
	if str(snapshot.get("faction_id", "")).is_empty() or str(goal.get("goal_id", "")) != str(proposal.get("goal_id", "")):
		return {"error": "wrong_goal_or_faction"}
	var steps: Array = []
	var known: Dictionary = {}
	for step in proposal.get("steps", []):
		if not step is Dictionary:
			return {"error": "invalid_step"}
		var sid := str(step.get("step_id", ""))
		if sid.is_empty() or known.has(sid):
			return {"error": "duplicate_step"}
		for dep in step.get("depends_on", []):
			if not known.has(str(dep)):
				return {"error": "invalid_dependency_order"}
		known[sid] = true
		steps.append({"step": step.duplicate(true), "dispatch_key": _key(str(snapshot["faction_id"]), plan_id, sid), "phase": PLANNED, "native_order_id": "", "updated_tick": int(snapshot.get("tick", 0)), "reason_code": ""})
	return {"schema_version": SCHEMA_VERSION, "faction_id": snapshot["faction_id"], "plan_id": plan_id, "goal_id": goal["goal_id"], "planner_id": proposal.get("planner_id", ""), "created_tick": snapshot.get("tick", 0), "snapshot_tick": snapshot.get("tick", 0), "steps": steps}

static func _key(faction_id: String, plan_id: String, step_id: String) -> String:
	# External dispatcher must use the same stable key convention as Rust dispatch_key.
	return "%d:%s:%d:%s:%d:%s" % [faction_id.length(), faction_id, plan_id.length(), plan_id, step_id.length(), step_id]

static func next_gate(ledger: Dictionary) -> Dictionary:
	var completed: Dictionary = {}
	for record in ledger.get("steps", []):
		var step: Dictionary = record["step"]
		var sid := str(step["step_id"])
		match str(record["phase"]):
			SUCCEEDED:
				completed[sid] = true
			FAILED, CANCELLED:
				return {"kind": "needs_replan", "step_id": sid, "reason_code": record.get("reason_code", "native_execution_failed")}
			PREPARED:
				return {"kind": "reconcile_prepared", "step_id": sid, "dispatch_key": record["dispatch_key"]}
			SUBMITTED, RUNNING:
				return {"kind": "await_native", "step_id": sid, "native_order_id": record["native_order_id"]}
			PLANNED:
				for dep in step.get("depends_on", []):
					if not completed.has(str(dep)):
						return {"kind": "await_dependencies", "step_id": sid}
				return {"kind": "ready", "step_id": sid, "dispatch_key": record["dispatch_key"], "action_id": step["action_id"]}
	return {"kind": "completed"}

static func prepare(ledger: Dictionary, step_id: String, tick: int) -> Dictionary:
	var gate := next_gate(ledger)
	if gate.get("kind") != "ready" or gate.get("step_id") != step_id:
		return {"error": "not_ready"}
	for record in ledger["steps"]:
		if record["step"]["step_id"] == step_id:
			if tick < int(record["updated_tick"]):
				return {"error": "tick_moved_backwards"}
			record["phase"] = PREPARED
			record["updated_tick"] = tick
			return {"dispatch_key": record["dispatch_key"]}
	return {"error": "unknown_step"}

static func acknowledge(ledger: Dictionary, step_id: String, key: String, order_id: String, tick: int) -> String:
	if order_id.is_empty():
		return "invalid_native_order"
	for record in ledger.get("steps", []):
		if record["step"]["step_id"] != step_id:
			continue
		if record["dispatch_key"] != key:
			return "wrong_dispatch_key"
		if tick < int(record["updated_tick"]):
			return "tick_moved_backwards"
		if not str(record["native_order_id"]).is_empty():
			return "" if record["native_order_id"] == order_id else "conflicting_order"
		if record["phase"] != PREPARED:
			return "invalid_transition"
		record["native_order_id"] = order_id
		record["phase"] = SUBMITTED
		record["updated_tick"] = tick
		return ""
	return "unknown_step"

static func apply_receipt(ledger: Dictionary, receipt: Dictionary) -> String:
	if receipt.get("plan_id") != ledger.get("plan_id"):
		return "wrong_plan"
	var incoming := str(receipt.get("status", ""))
	for record in ledger.get("steps", []):
		if record["step"]["step_id"] != receipt.get("step_id"):
			continue
		if int(receipt.get("tick", -1)) < int(record["updated_tick"]):
			return "tick_moved_backwards"
		if str(record["native_order_id"]).is_empty() or receipt.get("native_order_id") != record["native_order_id"]:
			return "conflicting_order"
		var old := str(record["phase"])
		var permitted := (old == SUBMITTED and incoming in [SUBMITTED, RUNNING, SUCCEEDED, FAILED, CANCELLED]) or (old == RUNNING and incoming in [RUNNING, SUCCEEDED, FAILED, CANCELLED]) or (old in [SUCCEEDED, FAILED, CANCELLED] and old == incoming)
		if not permitted:
			return "invalid_transition"
		record["phase"] = incoming
		record["reason_code"] = str(receipt.get("reason_code", ""))
		record["updated_tick"] = receipt["tick"]
		return ""
	return "unknown_step"
