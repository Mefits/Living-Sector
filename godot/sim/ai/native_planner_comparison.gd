extends RefCounted
## Frozen Rust: native/crates/sim_core/src/strategy/planning/comparison.rs
## Read-only comparison. Planner and validation callbacks are injected by integration.
## No plan may issue an order or spend money from this component.
const MODE := "read_only_same_native_snapshot"
const SOURCE_NOTE := "Predictions only. Legacy Genesis director uses a different decision horizon and cannot be ranked by this short stock probe."
const PLANNERS := ["htn", "telic_goap", "control_beam"]

func compare_planners(snapshot: Dictionary, goal: Dictionary, actions: Array, budget: Dictionary, planners: Dictionary, validator: Callable) -> Dictionary:
	var original := snapshot.duplicate(true)
	var catalogue := actions.duplicate(true)
	var results := []
	for planner_id in PLANNERS:
		var entry := {"planner_id": planner_id, "result": {}, "validation": "not_applicable_no_ready_plan", "path_action_ids": []}
		if not planners.has(planner_id) or not (planners[planner_id] is Callable) or not planners[planner_id].is_valid():
			entry.result = {"status": "unavailable", "explanation": "native planner adapter missing"}
			results.append(entry)
			continue
		var proposed: Variant = planners[planner_id].call(original.duplicate(true), goal.duplicate(true), catalogue.duplicate(true), budget.duplicate(true))
		if not (proposed is Dictionary):
			entry.result = {"status": "invalid_result"}
			results.append(entry)
			continue
		var result: Dictionary = proposed.duplicate(true)
		entry.result = result
		if String(result.get("status", "")).to_lower() == "ready":
			if not validator.is_valid():
				entry.validation = "rejected:missing_native_validator"
			else:
				var check: Variant = validator.call(original.duplicate(true), goal.duplicate(true), catalogue.duplicate(true), result.duplicate(true), budget.duplicate(true))
				if check == true:
					entry.validation = "valid_projected_plan"
				else:
					entry.validation = "rejected:" + str(check)
			if entry.validation == "valid_projected_plan":
				for step in result.get("steps", []):
					entry.path_action_ids.append(String(step.get("action_id", "")))
			else:
				entry.result.status = "rejected"
				entry.result.explanation = String(entry.result.get("explanation", "")) + "; " + entry.validation
		results.append(entry)
	return {"mode": MODE, "faction_id": original.get("faction_id", ""), "snapshot_tick": original.get("tick", 0), "goal_id": goal.get("goal_id", ""), "catalogue_size": actions.size(), "source_note": SOURCE_NOTE, "results": results}
